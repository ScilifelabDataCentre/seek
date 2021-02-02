require 'rest-client'
require 'redcarpet'
require 'redcarpet/render_strip'
require 'ro_crate_ruby'

module Seek
  module WorkflowExtractors
    class GitRepo < Base
      available_diagram_formats(png: 'image/png', svg: 'image/svg+xml', jpg: 'image/jpeg', default: :svg)

      def initialize(git_version, main_workflow_class: nil)
        @git_version = git_version
        @main_workflow_class = main_workflow_class
      end

      def can_render_diagram?
        @git_version.path_for_key(:diagram).present?
      end

      def diagram(format = nil)
        @git_version.file_contents(@git_version.path_for_key(:diagram))
      end

      def metadata
        # Use CWL description
        m = if @git_version.path_for_key(:abstract_cwl).present?
              abstract_cwl_extractor.metadata
            else
              main_workflow_extractor.metadata
            end

        m[:source_link_url] = @git_version.git_repository&.remote

        if @git_version.file_exists?('README.md')
          m[:description] ||= @git_version.file_contents('README.md')
        end

        return m
      end

      private

      def main_workflow_extractor
        return @main_workflow_extractor if @main_workflow_extractor

        workflow_class = @main_workflow_class
        extractor_class = workflow_class&.extractor_class || Seek::WorkflowExtractors::Base
        main_workflow_path = @git_version.path_for_key(:main_workflow)
        @main_workflow_extractor = main_workflow_path ? extractor_class.new(@git_version.file_contents(main_workflow_path)) : nil
      end

      def abstract_cwl_extractor
        return @abstract_cwl_extractor if @abstract_cwl_extractor

        abstract_cwl_path = @git_version.path_for_key(:abstract_cwl)
        @abstract_cwl_extractor = abstract_cwl_path ? Seek::WorkflowExtractors::CWL.new(@git_version.file_contents(abstract_cwl_path)) : nil
      end
    end
  end
end
