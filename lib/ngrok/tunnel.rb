require "ngrok/tunnel/version"
require "tempfile"

module Ngrok

  class NotFound < StandardError; end
  class FetchUrlError < StandardError; end
  class Error < StandardError; end

  class Tunnel

    class << self
      attr_reader :pid, :ngrok_url, :ngrok_url_https, :status
      attr_reader :type # http, tls, or tcp

      def init(params = {})
        # map old key 'port' to 'addr' to maintain backwards compatibility with versions 2.0.21 and earlier
        params[:addr] = params.delete(:port) if params.key?(:port)

        @params = {addr: 3001, timeout: 10, config: '/dev/null'}.merge(params)
        @status = :stopped unless @status
        @type = params[:type] || 'http'
      end

      def start(params = {})
        ensure_binary
        init(params)

        if stopped?
          @params[:log] = (@params[:log]) ? File.open(@params[:log], 'w+') : Tempfile.new('ngrok')
          command_string = "exec ngrok #{@type} " + ngrok_exec_params
          @pid = spawn(command_string)
          at_exit { Ngrok::Tunnel.stop }
          fetch_urls
        end

        @status = :running
        @ngrok_url
      end

      def stop
        if running?
          Process.kill(9, @pid)
          @ngrok_url = @ngrok_url_https = @pid = nil
          @status = :stopped
        end
        @status
      end

      def running?
        @status == :running
      end

      def stopped?
        @status == :stopped
      end

      def addr
        @params[:addr]
      end

      def port
        return addr if addr.is_a?(Numeric)
        addr.split(":").last.to_i
      end

      def log
        @params[:log]
      end

      def subdomain
        @params[:subdomain]
      end

      def authtoken
        @params[:authtoken]
      end

      def inherited(subclass)
        init
      end

      private

      def ngrok_exec_params
        exec_params = "-log=stdout -log-level=debug "
        exec_params << "-region=#{@params[:region]} " if @params[:region]
        exec_params << "-host-header=#{@params[:host_header]} " if @params[:host_header]
        exec_params << "-authtoken=#{@params[:authtoken]} " if @params[:authtoken]
        exec_params << "-subdomain=#{@params[:subdomain]} " if @params[:subdomain]
        exec_params << "-hostname=#{@params[:hostname]} " if @params[:hostname]
        exec_params << "-inspect=#{@params[:inspect]} " if @params.has_key? :inspect
        exec_params << "-config=#{@params[:config]} #{@params[:addr]} > #{@params[:log].path}"
      end

      def fetch_urls
        @params[:timeout].times do
          log_content = @params[:log].read
          result = log_content.scan(/URL:(.+)\sProto:(http|https|tcp)\s/)
          if !result.empty?
            result = Hash[*result.flatten].invert
            assign_urls(result)
            return @ngrok_url if @ngrok_url
          end

          error = log_content.scan(/msg="command failed" err="([^"]+)"/).flatten
          unless error.empty?
            self.stop
            raise Tunnel::Error, error.first
          end

          sleep 1
          @params[:log].rewind
        end
        raise FetchUrlError, "Unable to fetch external url"
        @ngrok_url
      end

      def ensure_binary
        `ngrok version`
      rescue Errno::ENOENT
        raise Ngrok::NotFound, "Ngrok binary not found"
      end

      def log_content_regex
        case @type
        when 'http'
          /URL:(.+)\sProto:(http|https)\s/
        when 'tls'
          /URL:(.+)\sProto:(http)\s/
        when 'tcp'
          /URL:(.+)\sProto:(tcp)\s/
        end
      end

      def assign_urls(result)
        case @type
        when 'http'
          @ngrok_url = result['http']
          @ngrok_url_https = result['https']
        when 'tls'
          @ngrok_url = result[@type]
          @ngrok_url_https = result[@type]
        when 'tcp'
          @ngrok_url = result[@type]
          @ngrok_url_https = result[@type]
        end
      end
    end # class << self

    init

  end
end
