module Apipie
  class ApipiesController < ActionController::Base
    layout Apipie.configuration.layout

    around_filter :set_script_name
    before_filter :authenticate

    def authenticate
      if Apipie.configuration.authenticate
        instance_eval(&Apipie.configuration.authenticate)
      end
    end

    def index

      params[:version] ||= Apipie.configuration.default_version

      get_format

      respond_to do |format|

        if Apipie.configuration.use_cache?
          render_from_cache
          return
        end

        @language = get_language

        Apipie.load_documentation if Apipie.configuration.reload_controllers? || (Rails.version.to_i >= 4.0 && !Rails.application.config.eager_load)

        I18n.locale = @language
        @doc = Apipie.to_json(params[:version], params[:resource], params[:method], @language)

        format.json do
          if @doc
            render :json => @doc
          else
            head :not_found
          end
        end

        format.html do
          unless @doc
            render 'apipie_404', :status => 404
            return
          end

          @versions = Apipie.available_versions
          @doc = @doc[:docs]
          @doc[:link_extension] = (@language ? ".#{@language}" : '')+Apipie.configuration.link_extension
          if @doc[:resources].blank?
            render "getting_started" and return
          end
          @resource = @doc[:resources].first if params[:resource].present?
          @method = @resource[:methods].first if params[:method].present?
          @languages = Apipie.configuration.languages
          if @resource && @method
            render 'method'
          elsif @resource
            render 'resource'
          elsif params[:resource].present? || params[:method].present?
            render 'apipie_404', :status => 404
          else
            render 'index'
          end
        end
      end
    end

    def apipie_checksum
    end

    private

    def get_language
      lang = nil
      [:resource, :method, :version].each do |par|
        if params[par]
          splitted = params[par].split('.')
          if splitted.length > 1 && Apipie.configuration.languages.include?(splitted.last)
            lang = splitted.last
            params[par].sub!(".#{lang}", '')
          end
        end
      end
      lang
    end

    def get_format
      [:resource, :method, :version].each do |par|
        if params[par]
          params[:format] = :html unless params[par].sub!('.html', '').nil?
          params[:format] = :json unless params[par].sub!('.json', '').nil?
        end
      end
      request.format = params[:format] if params[:format]
    end

    def render_from_cache
      path = Apipie.configuration.doc_base_url.dup
      # some params can contain dot, but only one in row
      if [:resource, :method, :format, :version].any? { |p| params[p].to_s.gsub(".", "") =~ /\W/ || params[p].to_s =~ /\.\./ }
        head :bad_request and return
      end

      path << "/" << params[:version] if params[:version].present?
      path << "/" << params[:resource] if params[:resource].present?
      path << "/" << params[:method] if params[:method].present?
      if params[:format].present?
        path << ".#{params[:format]}"
      else
        path << ".html"
      end

      # we sanitize the params before so in ideal case, this condition
      # will be never satisfied. It's here for cases somebody adds new
      # param into the path later and forgets about sanitation.
      if path =~ /\.\./
        head :bad_request and return
      end

      cache_file = File.join(Apipie.configuration.cache_dir, path)
      if File.exists?(cache_file)
        content_type = case params[:format]
                       when "json" then "application/json"
                       else "text/html"
                       end
        send_file cache_file, :type => content_type, :disposition => "inline"
      else
        Rails.logger.error("API doc cache not found for '#{path}'. Perhaps you have forgot to run `rake apipie:cache`")
        head :not_found
      end
    end

    def set_script_name
      Apipie.request_script_name = request.env["SCRIPT_NAME"]
      yield
    ensure
      Apipie.request_script_name = nil
    end
  end
end
