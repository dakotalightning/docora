require 'open3'
require 'ostruct'
require 'highline'
require 'json'

module Docora
  class Cli < Thor
    include Thor::Actions

    desc 'setup', 'dockerify your project'
    def setup(project = 'docker')
      do_setup(project)
    end

    desc 'up', 'start docker compose'
    def up(project = 'docker')
      do_up(project)
    end

    desc 'clean', 'clean you docker images and volumes'
    def clean(project = 'docker')
      do_clean(project)
    end

    desc 'version', 'Show version'
    def version
      puts Gem.loaded_specs['docora'].version.to_s
    end

    no_tasks do
      include Docora::Utility

      def self.source_root
        File.expand_path('../../',__FILE__)
      end

      def do_up(project)
        @ui = HighLine.new
        @project = project

        answer = ask("Do you want to clean? (y/n) ", ["y","n"])
        if answer == "y"
          do_clean(project)
        end

        docker_running?
        abort_with "run docora create" unless File.exists?('docker-compose.yml')

        say @ui.color("Starting containers", :green, :bold)
        run("docker-compose up -d", verbose: false)

        say @ui.color("--> booting containers ...", :green, :bold)

        say @ui.color("done", :green, :bold)
        run("docker-compose ps", verbose: false)
      end

      def do_clean(project)
        @ui = HighLine.new
        @project = project

        docker_running?

        images = run('docker images -qf dangling=true', capture: true, verbose: false)
        volumes = run('docker volume ls -qf dangling=true', capture: true, verbose: false)

        if images.empty?
          say @ui.color("no images", :green, :bold)
        else
          say "cleaning images"
          say @ui.color("--> cleaning images", :blue, :bold)
          run(`docker rmi -f #{images}`, verbose: false)
        end

        if volumes.empty?
          say @ui.color("no volumes", :green, :bold)
        else
          say @ui.color("--> cleaning volumes", :blue, :bold)
          run(`docker volume rm #{volumes}`, verbose: false)
        end

        say @ui.color("Done", :green, :bold)
      end

      def do_setup(project)
        @ui = HighLine.new
        @project = project

        docker_running?

        allowed_ruby_versions = [
          "2",
          "2.0.0",
          "2.1",
          "2.1.10",
          "2.1.6",
          "2.1.8",
          "2.2.6",
          "2.3",
          "2.3.0",
          "2.3.1",
          "2.3.2",
          "2.3.3",
          "2.3.4",
          "2.4",
          "2.4.1"
        ]

        if File.exists?('.gitignore')
          append_to_file ".gitignore", "#{project}/"
        else
          create_file ".gitignore", "#{project}/"
        end

        if File.exists?('.ruby-version')
          ruby_version = File.read('.ruby-version').strip
        elsif File.exists?('Gemfile')
          ruby_version = File.read('Gemfile').split("\n").first.gsub("ruby", "").strip.gsub("'", "")
        # else
        #   ruby_version = ask_menu("What ruby version?", ["2.0.0",  "2.1.6", "2.2.6", "2.3.3", "2.4.0"])
        end

        abort_with "Unsupported Ruby version, allowed ruby versions: #{allowed_ruby_versions.join(", ")}"  unless allowed_ruby_versions.include?(ruby_version)

        if File.exists?('.env')
          append_to_file ".env", "JOB_WORKER_URL=redis://redis:6379/0"
        else
          create_file ".env", "JOB_WORKER_URL=redis://redis:6379/0"
        end

        dockerfile = "FROM ruby:#{ruby_version}\n"
        dockerfile += "RUN apt-get update && apt-get install -qq -y --no-install-recommends build-essential nodejs libpq-dev libqt4-dev libqtwebkit-dev\n"
        dockerfile += "ENV INSTALL_PATH /var/rails_app\n"
        dockerfile += "RUN mkdir -p $INSTALL_PATH\n"
        dockerfile += "WORKDIR $INSTALL_PATH\n"
        dockerfile += "COPY Gemfile Gemfile.lock ./\n"
        dockerfile += "RUN bundle install\n"

        dockerignore = ".git\n"
        dockerignore += ".dockerignore\n"
        dockerignore += ".byebug_history\n"
        dockerignore += "/log/*\n"
        dockerignore += "/tmp/*\n"
        dockerignore += "#{project}/\n"
        dockerignore += "/#{project}/*\n"

        create_file "Dockerfile", dockerfile
        create_file ".dockerignore", dockerignore
        create_file "docker-compose.yml", YAML.dump(docker_compose)

        answer = ask("Want to run rake db:setup? (y/n) ", ["y","n"])
        if answer == "y"
          do_up(project)
          run("docker-compose exec web rake db:setup", verbose: false)
        end
      end

      def docker_compose
        compose = {}
        compose["version"] = '2'
        services = {}
        db = ask_menu("What database?", ["postgres", "mysql"])
        if db == "mysql"
          services["mysql"] = {
            image: 'mysql:5.7.17',
            ports: ["13306:3306"],
            environment: {
              MYSQL_ROOT_PASSWORD: 'root',
              MYSQL_DATABASE: 'root'
            },
            volumes: ["./#{@project}/data/mysql:/var/lib/mysql"]
          }
        elsif db == "postgres"
          services["postgres"] = {
            image: 'postgres:9.5',
            ports: ["5432:5432"],
            environment: {
              POSTGRES_USER: 'root',
              POSTGRES_PASSWORD: 'root'
            },
            volumes: ["./#{@project}/data/postgres:/var/lib/postgresql/data"]
          }
        end

        redis = ask("Are you using redis? (y/n) ", ["y","n"])
        if redis == "y"
          services["redis"] = {
            image: 'redis:3.0.7-alpine',
            ports: ["6379:6379"],
            volumes: ["./#{@project}/data/redis:/data"]
          }
        end

        depends_on = []
        if redis == "y"
          depends_on.push('redis')
        end
        depends_on.push(db)

        sidekiq = ask("Are you using sidekiq? (y/n) ", ["y","n"])
        if sidekiq == "y"
          services["sidekiq"] = {
            build: '.',
            command: 'bash -c "bundle exec sidekiq -C config/sidekiq.yml"',
            env_file: ['.env'],
            volumes: ['.:/var/rails_app'],
            depends_on: depends_on
          }
        end

        services["web"] = {
          build: '.',
          ports: ['3000:3000'],
          command: 'bash -c "bundle exec rails s -b 0.0.0.0"',
          env_file: ['.env'],
          volumes: ['.:/var/rails_app'],
          depends_on: depends_on
        }

        compose["services"] = services
        JSON.parse(compose.to_json)
      end

      def docker_running?
        version = run('docker version', capture: true, verbose: false)
        docker_version = YAML.load(version)
        abort_with "Please make sure docker is running"  unless docker_version["Server"]
      end

      def ask(question, answer_type, &details)
        @ui.ask(@ui.color(question, :green, :bold), answer_type, &details)
      end

      def ask_menu(question, choices)
        @ui.choose do |menu|
          menu.prompt = "#{@ui.color(question, :green, :bold)} "
          choices.each { |n| menu.choice(n) }
        end
      end

    end

  end
end
