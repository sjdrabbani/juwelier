require 'git'
require 'erb'

require 'net/http'
require 'uri'

require 'jeweler/generator/bacon_mixin'
require 'jeweler/generator/micronaut_mixin'
require 'jeweler/generator/minitest_mixin'
require 'jeweler/generator/rspec_mixin'
require 'jeweler/generator/shoulda_mixin'
require 'jeweler/generator/testunit_mixin'

require 'jeweler/generator/rdoc_mixin'
require 'jeweler/generator/yard_mixin'

class Jeweler
  class NoGitUserName < StandardError
  end
  class NoGitUserEmail < StandardError
  end
  class FileInTheWay < StandardError
  end
  class NoGitHubRepoNameGiven < StandardError
  end
  class NoGitHubUser < StandardError
  end
  class NoGitHubToken < StandardError
  end
  class GitInitFailed < StandardError
  end    

  class Generator    
    require 'jeweler/generator/options'
    require 'jeweler/generator/application'

    attr_accessor :target_dir, :user_name, :user_email, :summary,
                  :description, :project_name, :github_username, :github_token,
                  :repo, :should_create_repo, 
                  :testing_framework, :documentation_framework,
                  :should_use_cucumber, :should_setup_gemcutter,
                  :should_setup_rubyforge, :should_use_reek, :should_use_roodi,
                  :development_dependencies

    DEFAULT_TESTING_FRAMEWORK = :shoulda
    DEFAULT_DOCUMENTATION_FRAMEWORK = :rdoc

    def initialize(project_name, options = {})
      if project_name.nil? || project_name.squeeze.strip == ""
        raise NoGitHubRepoNameGiven
      end

      self.development_dependencies = []

      self.project_name   = project_name

      self.testing_framework  = (options[:testing_framework] || DEFAULT_TESTING_FRAMEWORK).to_sym
      self.documentation_framework = options[:documentation_framework] || DEFAULT_DOCUMENTATION_FRAMEWORK
      begin
        generator_mixin_name = "#{self.testing_framework.to_s.capitalize}Mixin"
        generator_mixin = self.class.const_get(generator_mixin_name)
        extend generator_mixin
      rescue NameError => e
        raise ArgumentError, "Unsupported testing framework (#{testing_framework})"
      end

      begin
        generator_mixin_name = "#{self.documentation_framework.to_s.capitalize}Mixin"
        generator_mixin = self.class.const_get(generator_mixin_name)
        extend generator_mixin
      rescue NameError => e
        raise ArgumentError, "Unsupported documentation framework (#{documentation_framework})"
      end


      self.target_dir             = options[:directory] || self.project_name

      self.should_create_repo     = options[:create_repo]
      self.summary                = options[:summary] || 'TODO: one-line summary of your gem'
      self.description            = options[:description] || 'TODO: longer description of your gem'
      self.should_use_cucumber    = options[:use_cucumber]
      self.should_use_reek        = options[:use_reek]
      self.should_use_roodi       = options[:use_roodi]
      self.should_setup_gemcutter = options[:gemcutter]
      self.should_setup_rubyforge = options[:rubyforge]

      development_dependencies << "cucumber" if should_use_cucumber

      use_user_git_config
      
    end

    def run
      create_files
      gitify
      $stdout.puts "Jeweler has prepared your gem in #{target_dir}"
      if should_create_repo
        create_and_push_repo
        $stdout.puts "Jeweler has pushed your repo to #{project_homepage}"
        enable_gem_for_repo
        $stdout.puts "Jeweler has enabled gem building for your repo"
      end
    end

    def git_remote
      "git@github.com:#{github_username}/#{project_name}.git"
    end

    def project_homepage
      "http://github.com/#{github_username}/#{project_name}"
    end
    
    def constant_name
      self.project_name.split(/[-_]/).collect{|each| each.capitalize }.join
    end

    def lib_filename
      "#{project_name}.rb"
    end

    def require_name
      self.project_name
    end

    def file_name_prefix
      self.project_name.gsub('-', '_')
    end

    def lib_dir
      'lib'
    end

    def feature_filename
      "#{project_name}.feature"
    end

    def steps_filename
      "#{project_name}_steps.rb"
    end

    def features_dir
      'features'
    end

    def features_support_dir
      File.join(features_dir, 'support')
    end

    def features_steps_dir
      File.join(features_dir, 'step_definitions')
    end

  protected

    # This is in a separate method so we can stub it out during testing
    def read_git_config
      Git.global_config
    end

  private
    def create_files
      unless File.exists?(target_dir) || File.directory?(target_dir)
        FileUtils.mkdir target_dir
      else
        raise FileInTheWay, "The directory #{target_dir} already exists, aborting. Maybe move it out of the way before continuing?"
      end


      output_template_in_target '.gitignore'
      output_template_in_target 'Rakefile'
      output_template_in_target 'LICENSE'
      output_template_in_target 'README.rdoc'
      output_template_in_target '.document'

      mkdir_in_target           lib_dir
      touch_in_target           File.join(lib_dir, lib_filename)

      mkdir_in_target           test_dir
      output_template_in_target File.join(testing_framework.to_s, 'helper.rb'), File.join(test_dir, test_helper_filename)
      output_template_in_target File.join(testing_framework.to_s, 'flunking.rb'), File.join(test_dir, test_filename)

      if should_use_cucumber
        mkdir_in_target           features_dir
        output_template_in_target File.join(%w(features default.feature)), File.join('features', feature_filename)

        mkdir_in_target           features_support_dir
        output_template_in_target File.join(features_support_dir, 'env.rb')

        mkdir_in_target           features_steps_dir
        touch_in_target           File.join(features_steps_dir, steps_filename)
      end

    end

    def use_user_git_config
      git_config = self.read_git_config

      unless git_config.has_key? 'user.name'
        raise NoGitUserName
      end
      
      unless git_config.has_key? 'user.email'
        raise NoGitUserEmail
      end
      
      unless git_config.has_key? 'github.user'
        raise NoGitHubUser
      end
      
      if should_create_repo
        unless git_config.has_key? 'github.token'
          raise NoGitHubToken
        end
      end

      self.user_name       = git_config['user.name']
      self.user_email      = git_config['user.email']
      self.github_username = git_config['github.user']
      self.github_token    = git_config['github.token']
    end

    def output_template_in_target(source, destination = source)
      final_destination = File.join(target_dir, destination)

      template_contents = File.read(File.join(template_dir, source))
      template = ERB.new(template_contents, nil, '<>')

      template_result = template.result(binding).gsub(/\n\n\n+/, "\n\n")

      File.open(final_destination, 'w') {|file| file.write(template_result)}

      $stdout.puts "\tcreate\t#{destination}"
    end

    def template_dir
      File.join(File.dirname(__FILE__), 'templates')
    end

    def mkdir_in_target(directory)
      final_destination = File.join(target_dir, directory)

      FileUtils.mkdir final_destination

      $stdout.puts "\tcreate\t#{directory}"
    end

    def touch_in_target(destination)
      final_destination = File.join(target_dir, destination)
      FileUtils.touch  final_destination
      $stdout.puts "\tcreate\t#{destination}"
    end

    def gitify
      saved_pwd = Dir.pwd
      Dir.chdir(target_dir)
      begin
        begin
          @repo = Git.init()
        rescue Git::GitExecuteError => e
          raise GitInitFailed, "Encountered an error during gitification. Maybe the repo already exists, or has already been pushed to?"
        end

        begin
          @repo.add('.')
        rescue Git::GitExecuteError => e
          #raise GitAddFailed, "There was some problem adding this directory to the git changeset"
          raise
        end

        begin
          @repo.commit "Initial commit to #{project_name}."
        rescue Git::GitExecuteError => e
          raise
        end

        begin
          @repo.add_remote('origin', git_remote)
        rescue Git::GitExecuteError => e
          puts "Encountered an error while adding origin remote. Maybe you have some weird settings in ~/.gitconfig?"
          raise
        end
      ensure
        Dir.chdir(saved_pwd)
      end
    end
    
    def create_and_push_repo
      Net::HTTP.post_form URI.parse('http://github.com/api/v2/yaml/repos/create'),
                                'login' => github_username,
                                'token' => github_token,
                                'description' => summary,
                                'name' => project_name
      # TODO do a HEAD request to see when it's ready
      @repo.push('origin')
    end

    def enable_gem_for_repo
      url = "https://github.com/#{github_username}/#{project_name}/update"
      `curl -F 'login=#{github_username}' -F 'token=#{github_token}' -F 'field=repository_rubygem' -F 'value=1' #{url} 2>/dev/null`
      # FIXME use NET::HTTP instead of curl
      #Net::HTTP.post_form URI.parse(url),
                                #'login' => github_username,
                                #'token' => github_token,
                                #'field' => 'repository_rubygem',
                                #'value' => '1'
    end

  end
end
