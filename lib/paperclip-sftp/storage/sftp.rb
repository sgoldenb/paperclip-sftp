module Paperclip
  module Storage
    # SFTP (Secure File Transfer Protocol) storage for Paperclip.
    #
    module Sftp

      # SFTP storage expects a hash with following options:
      # :host, :user, :password, :port.
      #
      def self.extended(base)
        begin
          require "net/sftp"
        rescue LoadError => e
          e.message << "(You may need to install net-sftp gem)"
          raise e
        end unless defined?(Net::SFTP)

        base.instance_exec do
          @sftp_options = options[:sftp_options] || {}
        end
      end

      # Make SFTP connection, but use current one if exists.
      #
      def sftp(&block)
        Net::SFTP.start(
          @sftp_options[:host],
          @sftp_options[:user],
          password: @sftp_options[:password],
          port: @sftp_options[:port],
          keys: @sftp_options[:keys], 
	  &block
        )
      end

      def exists?(style = default_style)
        if original_filename
          files = sftp.dir.entries(File.dirname(path(style))).map(&:name)
          files.include?(File.basename(path(style)))
        else
          false
        end
      rescue Net::SFTP::StatusException => e
        false
      end

      def copy_to_local_file(style, local_dest_path)
        log("copying #{path(style)} to local file #{local_dest_path}")

        sftp do |s|
          s.download!(path(style), local_dest_path)
        end
      rescue Net::SFTP::StatusException => e
        warn("#{e} - cannot copy #{path(style)} to local file #{local_dest_path}")
        false
      end

      def flush_writes #:nodoc:
	sftp do |s|
          @queued_for_write.each do |style, file|
            mkdir_p(File.dirname(path(style)), s)
            log("uploading #{file.path} to #{path(style)}")
            s.upload!(file.path, path(style))
            s.setstat!(path(style), :permissions => 0644)
          end
        end

        after_flush_writes # allows attachment to clean up temp files
        @queued_for_write = {}
      end

      def flush_deletes #:nodoc:
	sftp do |s|
          @queued_for_delete.each do |path|
            begin
              log("deleting file #{path}")
              s.remove(path).wait
            rescue Net::SFTP::StatusException => e
              # ignore file-not-found, let everything else pass
            end

            begin
            path = File.dirname(path)
              while sftp.dir.entries(path).delete_if { |e| e.name =~ /^\./ }.empty?
                s.rmdir(path).wait
                path = File.dirname(path)
              end
            rescue Net::SFTP::StatusException => e
              # stop trying to remove parent directories
            end
          end
        end
        @queued_for_delete = []
      end

      private

      # Create directory structure.
      #
      def mkdir_p(remote_directory, sftp)
        log("mkdir_p for #{remote_directory}")
        root_directory = '/'
        remote_directory.split('/').each do |directory|
          next if directory.blank?
          unless sftp.dir.entries(root_directory).map(&:name).include?(directory)
            sftp.mkdir!("#{root_directory}#{directory}")
          end
          root_directory += "#{directory}/"
        end
      end

    end
  end
end
