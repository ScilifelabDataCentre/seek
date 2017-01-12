module Seek
  module Openbis
    # Behaviour relevant to a content blob that represents and openbis entity
    # FIXME: wanted to call ContentBlob but rails loader didn't like it and got confused
    # ... over the model ContentBlob disregarding the namespacing. Need to investigate why?
    module Blob
      def openbis?
        url && URI.parse(url).scheme == 'openbis' && url.split(':').count == 4
      end

      def openbis_dataset
        return nil unless openbis?
        parts = url.split(':')
        endpoint = OpenbisEndpoint.find(parts[1])
        endpoint.space # temporarily needed to authenticate
        Seek::Openbis::Dataset.new(parts[3])
      end

      def search_terms
        super | openbis_search_terms
      end

      #overide and ignore the url
      def url_search_terms
        if openbis?
          []
        else
          super
        end
      end

      private

      def openbis_search_terms
        return [] unless openbis? && dataset=openbis_dataset
        terms = [dataset.perm_id,dataset.dataset_type_code,dataset.dataset_type_description, dataset.experiment_id]
        terms | dataset.dataset_files_no_directories.collect do |file|
          [file.perm_id, file.path, file.filename]
        end.flatten
      end

    end
  end
end
