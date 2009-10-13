require File.dirname(__FILE__) + '/../test_helper'

class AssayTest < ActiveSupport::TestCase
  fixtures :all

  test "sops association" do
    assay=assays(:metabolomics_assay)
    assert_equal 2,assay.sops.size
    assert assay.sops.include?(sops(:my_first_sop))
    assert assay.sops.include?(sops(:sop_with_fully_public_policy))

  end

  test "orgnanism association" do
    assay=assays(:metabolomics_assay)
    assert_equal organisms(:Saccharomyces_cerevisiae),assay.organism
    assay=assays(:metabolomics_assay2)
    assert_nil assay.organism
  end

  test "related investigation" do
    assay=assays(:metabolomics_assay)
    assert_not_nil assay.investigation
    assert_equal investigations(:metabolomics_investigation),assay.investigation
  end

  test "related project" do
    assay=assays(:metabolomics_assay)
    assert_not_nil assay.project
    assert_equal projects(:sysmo_project),assay.project
  end
  

  test "validation" do
    assay=Assay.new(:title=>"test",
      :assay_type=>assay_types(:metabolomics),
      :technology_type=>technology_types(:gas_chromatography),
      :study => studies(:metabolomics_study),
      :owner => people(:person_for_model_owner))
    
    assert assay.valid?

    assay.title=""
    assert !assay.valid?

    assay.title=nil
    assert !assay.valid?

    assay.title=assays(:metabolomics_assay).title
    assert !assay.valid?

    assay.title="test"
    assay.assay_type=nil
    assert !assay.valid?

    assay.assay_type=assay_types(:metabolomics)

    assert assay.valid?

    assay.study=nil
    assert !assay.valid?
    assay.study=studies(:metabolomics_study)

    assay.technology_type=nil
    assert !assay.valid?

    assay.technology_type=technology_types(:gas_chromatography)
    assert assay.valid?

    assay.owner=nil
    assert !assay.valid?
    
  end

  test "assay with no study has nil study and project" do
    a=assays(:assay_with_no_study_or_files)
    assert_nil a.study
    assert_nil a.project
  end

  test "can delete?" do
    assert assays(:assay_with_no_study_or_files).can_delete?(users(:model_owner))
    assert assays(:assay_with_just_a_study).can_delete?(users(:model_owner))
    assert !assays(:assay_with_no_study_but_has_some_files).can_delete?(users(:model_owner))
    assert !assays(:assay_with_no_study_but_has_some_sops).can_delete?(users(:model_owner))
  end

  test "assets" do
    sops=[]
    data_files=[]
    sops << sops(:my_first_sop)
    sops << sops(:sop_with_fully_public_policy)
    data_files << data_files(:picture)

    #to make them versioned
    sops.each{|s| s.save_as_new_version}
    data_files.each{|df| df.save_as_new_version}

    assay=assays(:metabolomics_assay)
    assert_equal 0,assay.assets.size

    assay.assets << sops[0].asset
    assay.assets << sops[1].asset
    assay.assets << data_files[0].asset

    assert_equal 3,assay.assets.size

  end

  test "sops" do
    sops=[]
    data_files=[]
    sops << sops(:my_first_sop)
    sops << sops(:sop_with_fully_public_policy)
    data_files << data_files(:picture)

    #to make them versioned
    sops.each{|s| s.save_as_new_version}
    data_files.each{|df| df.save_as_new_version}

    assay=Assay.new(:title=>"fred",:study=>studies(:study_with_no_assays))
    assert_equal 0,assay.sops.size

    assay.assets << sops[0].asset
    assay.assets << sops[1].asset
    assay.assets << data_files[0].asset

    assay.save

    assert_equal 2,assay.versioned_sops.size
    assert assay.sops2.contains?(sops[0])
    assert assay.sops2.contains?(sops[1])
    
  end


end
