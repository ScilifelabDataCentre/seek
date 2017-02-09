require 'seek/custom_exception'

class ProjectsController < ApplicationController

  include WhiteListHelper
  include Seek::IndexPager
  include CommonSweepers
  include Seek::DestroyHandling

  before_filter :find_requested_item, :only=>[:show,:admin, :edit,:update, :destroy,:asset_report,:admin_members,
                                              :admin_member_roles,:update_members,:storage_report]
  before_filter :find_assets, :only=>[:index]
  before_filter :auth_to_create, :only=>[:new,:create]
  before_filter :is_user_admin_auth, :only => [:manage, :destroy]
  before_filter :editable_by_user, :only=>[:edit,:update]
  before_filter :administerable_by_user, :only =>[:admin,:admin_members,:admin_member_roles,:update_members,:storage_report]
  before_filter :auth_params,:only=>[:update]
  before_filter :member_of_this_project, :only=>[:asset_report],:unless=>:admin?

  skip_before_filter :project_membership_required

  cache_sweeper :projects_sweeper,:only=>[:update,:create,:destroy]
  include Seek::BreadCrumbs

  include Seek::IsaGraphExtensions

  respond_to :html

  def asset_report
    @no_sidebar=true
    project_assets = @project.assets | @project.assays | @project.studies | @project.investigations
    @types=[DataFile,Model,Sop,Presentation,Investigation,Study,Assay]
    @public_assets = {}
    @semi_public_assets = {}
    @restricted_assets = {}
    @types.each do |type|
      action = type.is_isa? ? "view" : "download"
      @public_assets[type] = type.all_authorized_for action, nil, @project
      #to reduce the initial list - will start with all assets that can be seen by the first user fouund to be in a project
      user = User.all.detect{|user| !user.try(:person).nil? && !user.person.projects.empty?}
      projects_shared = user.nil? ? [] : type.all_authorized_for("download", user, @project)
      #now select those with a policy set to downloadable to all-sysmo-users
      projects_shared  = projects_shared.select do |item|
        access_type = type.is_isa? ? Policy::VISIBLE : Policy::ACCESSIBLE
        (item.policy.sharing_scope == Policy::ALL_USERS && item.policy.access_type == access_type)
      end
      #just those shared with sysmo but NOT shared publicly
      @semi_public_assets[type]  = projects_shared  - @public_assets[type]

      all = project_assets.select{|a|a.class==type}
      @restricted_assets[type] = all - (@semi_public_assets[type] | @public_assets[type])
    end

    #inlinked assets - either not linked to an assay or publication, or in the case of assays not linked to a publication or other assets
    @types_for_unlinked = [DataFile, Model, Sop, Assay]
    @unlinked_to_publication={}
    @unlinked_to_assay={}
    @unlinked_assets={}
    @types_for_unlinked.each do |type|
      @unlinked_assets[type] = []
      @unlinked_to_publication[type] = []
      @unlinked_to_assay[type] = []
    end
    project_assets.each do |asset|
      if @types_for_unlinked.include?(asset.class)
        if asset.publications.empty?
          @unlinked_to_publication[asset.class] << asset
        end
        if (!asset.respond_to?(:assays) || asset.assays.empty?) && (!asset.is_isa? || asset.assets.empty?)
          @unlinked_to_assay[asset.class] << asset
        end
      end
    end
    #get those that are unlinked to either
    @types_for_unlinked.each do |type|
      @unlinked_assets[type]=@unlinked_to_assay[type] & @unlinked_to_publication[type]
    end


    respond_to do |format|
      format.html {render :template=>"projects/asset_report/report"}
    end
  end

  def admin
    
    respond_to do |format|
      format.html # admin.html.erb
    end
  end

  # GET /projects/1
  # GET /projects/1.xml
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.rdf { render :template=>'rdf/show'}
      format.xml
      format.json { render :text=>@project.to_json}
    end
  end

  # GET /projects/new
  # GET /projects/new.xml
  def new
    @project = Project.new

    possible_unsaved_data = "unsaved_#{@project.class.name}_#{@project.id}".to_sym
    if session[possible_unsaved_data]
      # if user was redirected to this 'edit' page from avatar upload page - use session
      # data; alternatively, user has followed some other route - hence, unsaved session
      # data is most probably not relevant anymore
      if params[:use_unsaved_session_data]
        # NB! these parameters are admin settings and can *occasionally* be used by super-users -
        # regular users won't (and MUST NOT) be able to use these; it's not likely for admins
        # or super-users to modify these along with participating institutions - therefore,
        # it's better not to update these from session
        #
        # this was also causing a bug: when "upload new avatar" pressed, then new picture
        # uploaded and redirected back to edit profile page; at this poing *new* records
        # in the DB for institutions that participate in this project would already be created, which is an
        # error (if the following line is ever to be removed, the bug needs investigation)
        session[possible_unsaved_data][:project].delete(:institution_ids)

        # update those attributes of a project that we want to be updated from the session
        @project.attributes = session[possible_unsaved_data][:project]
        @project.organism_list = session[possible_unsaved_data][:organism][:list] if session[possible_unsaved_data][:organism]
      end

      # clear the session data anyway
      session[possible_unsaved_data] = nil
    end
  end

  # GET /projects/1/edit
  def edit
    
    possible_unsaved_data = "unsaved_#{@project.class.name}_#{@project.id}".to_sym
    if session[possible_unsaved_data]
      # if user was redirected to this 'edit' page from avatar upload page - use session
      # data; alternatively, user has followed some other route - hence, unsaved session
      # data is most probably not relevant anymore
      if params[:use_unsaved_session_data]
        # NB! these parameters are admin settings and can *occasionally* be used by super-users -
        # regular users won't (and MUST NOT) be able to use these; it's not likely for admins
        # or super-users to modify these along with participating institutions - therefore,
        # it's better not to update these from session
        #
        # this was also causing a bug: when "upload new avatar" pressed, then new picture
        # uploaded and redirected back to edit profile page; at this poing *new* records
        # in the DB for institutions that participate in this project would already be created, which is an
        # error (if the following line is ever to be removed, the bug needs investigation)
        session[possible_unsaved_data][:project].delete(:institution_ids)
        
        # update those attributes of a project that we want to be updated from the session
        @project.attributes = session[possible_unsaved_data][:project]
        @project.organism_list = session[possible_unsaved_data][:organism][:list] if session[possible_unsaved_data][:organism]
      end
      
      # clear the session data anyway
      session[possible_unsaved_data] = nil
    end
  end

  # POST /projects
  # POST /projects.xml
  def create
    #strip out programme_id if permissions do not allow
    unless params[:project][:programme_id].blank?
      unless Programme.find(params[:project][:programme_id]).can_manage?
        params[:project].delete(:programme_id)
      end
    end
    @project = Project.new(params[:project])

    @project.default_policy.set_attributes_with_sharing(params[:policy_attributes])



    respond_to do |format|
      if @project.save
        if params[:default_member] && params[:default_member][:add_to_project] && params[:default_member][:add_to_project]=='1'
          institution = Institution.find(params[:default_member][:institution_id])
          person = current_person
          person.add_to_project_and_institution(@project,institution)
          person.is_project_administrator=true,@project
          disable_authorization_checks{person.save}
        end
        flash[:notice] = "#{t('project')} was successfully created."
        format.html { redirect_to(@project) }
        format.xml  { render :xml => @project, :status => :created, :location => @project }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @project.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /projects/1
  # PUT /projects/1.xml
  def update

    @project.default_policy = (@project.default_policy || Policy.default).set_attributes_with_sharing(params[:policy_attributes]) if params[:policy_attributes]

    begin
      respond_to do |format|
        if @project.update_attributes(params[:project])
          if (Seek::Config.email_enabled && !@project.can_be_administered_by?(current_user))
            ProjectChangedEmailJob.new(@project).queue_job
          end
          expire_resource_list_item_content
          flash[:notice] = "#{t('project')} was successfully updated."
          format.html { redirect_to(@project) }
          format.xml  { head :ok }
        else
          format.html { render :action => "edit" }
          format.xml  { render :xml => @project.errors, :status => :unprocessable_entity }
        end
      end
    rescue WorkGroupDeleteError=>e
      respond_to do |format|
        flash[:error] = e.message
        format.html { redirect_to(@project) }
      end
    end
  end

  def manage
    @projects = Project.all
    respond_to do |format|
      format.html
      format.xml{render :xml=>@projects}
    end
  end

  
  # returns a list of institutions for a project in JSON format
  def request_institutions
    # listing institutions for a project is public data, but still
    # we require login to protect from unwanted requests
    
    project_id = white_list(params[:id])
    institution_list = nil
    
    begin
      project = Project.find(project_id)
      institution_list = project.work_groups.collect{|w| [w.institution.title, w.institution.id, w.id]}
      success = true
    rescue ActiveRecord::RecordNotFound
      # project wasn't found
      success = false
    end
    
    respond_to do |format|
      format.json {
        if success
          render :json => {:status => 200, :institution_list => institution_list }
        else
          render :json => {:status => 404, :error => "Couldn't find #{t('project')} with ID #{project_id}."}
        end
      }
    end
  end

  def admin_members
    respond_with(@project)
  end

  def admin_member_roles
    respond_with(@project)
  end

  def update_members
    add_and_remove_members_and_institutions
    flag_memberships
    update_administrative_roles

    flash[:notice]="The members and institutions of the #{t('project').downcase} '#{@project.title}' have been updated"

    respond_with(@project) do |format|
      format.html {redirect_to project_path(@project)}
    end
  end

  def update_administrative_roles
    unless params[:project].blank?
      #need convverting to an array from a comma separated string
      params[:project].keys.each do |k|
        params[:project][k] = params[:project][k].split(",")
      end
      @project.update_attributes(params[:project])
    end
  end

  def storage_report
    respond_with do |format|
      format.html { render partial: 'projects/storage_usage_content',
                           locals: { project: @project, standalone: true } }
    end
  end

  private

  def add_and_remove_members_and_institutions
    groups_to_remove = params[:group_memberships_to_remove] || []
    people_and_institutions_to_add = params[:people_and_institutions_to_add] || []
    groups_to_remove.each do |group|
      group_membership = GroupMembership.find(group)
      if group_membership && group_membership.person_can_be_removed?
        #this slightly strange bit of code is required to trigger and after_remove callback, which should be revisted
        #
        # Finn: http://guides.rubyonrails.org/association_basics.html#the-has-many-through-association
        #       "Automatic deletion of join models is direct, no destroy callbacks are triggered."
        group_membership.person.group_memberships.destroy(group_membership)
      end
    end

    people_and_institutions_to_add.each do |new_info|
      json = JSON.parse(new_info)
      person_id = json["person_id"]
      institution_id = json["institution_id"]
      person = Person.find(person_id)
      institution = Institution.find(institution_id)
      unless person.nil? || institution.nil?
        person.add_to_project_and_institution(@project, institution)
        person.save!
      end
    end
  end

  def flag_memberships
    unless params[:memberships_to_flag].blank?
      GroupMembership.where(:id => params[:memberships_to_flag].keys).includes(:work_group).each do |membership|
        if membership.work_group.project_id == @project.id # Prevent modification of other projects' memberships
          left_at = params[:memberships_to_flag][membership.id.to_s][:time_left_at]
          membership.update_attributes(:time_left_at => left_at)
        end
      end
    end
  end

  def editable_by_user
    @project = Project.find(params[:id])
    unless User.admin_logged_in? || @project.can_be_edited_by?(current_user)
      error("Insufficient privileges", "is invalid (insufficient_privileges)")
      return false
    end
  end

  def member_of_this_project
    @project = Project.find(params[:id])
    if @project.nil? || !@project.has_member?(current_user)
      flash[:error]="You are not a member of this #{t('project')}, so cannot access this page."
      redirect_to project_path(@project)
      false
    else
      true
    end

  end

  def administerable_by_user
    @project = Project.find(params[:id])
    unless @project.can_be_administered_by?(current_user)
      error("Insufficient privileges", "is invalid (insufficient_privileges)")
      return false
    end
  end

  def auth_params
    restricted_params={:policy_attributes => User.admin_logged_in?,
                       :site_root_uri => User.admin_logged_in?,
                       :site_username => User.admin_logged_in?,
                       :site_password => User.admin_logged_in?,
                       :institution_ids => (User.admin_logged_in? || @project.can_be_administered_by?(current_user))}
    restricted_params.each do |param, allowed|
      params[:project].delete(param) if params[:project] and not allowed
      params.delete param if params and not allowed
    end
  end


end
