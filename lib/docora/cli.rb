require 'open3'
require 'ostruct'
require 'highline'

module Docora
  class Cli < Thor
    include Thor::Actions

    desc 'create', 'Create niso project'
    def create(project = 'docker')
      do_create(project)
    end

    desc 'version', 'Show version'
    def version
      puts Gem.loaded_specs['niso'].version.to_s
    end

    no_tasks do
      include Docora::Utility

      def self.source_root
        File.expand_path('../../',__FILE__)
      end

      def do_create(project)
        @ui = HighLine.new

        if File.exists?('.ruby-version')
          ruby_version = File.read('.ruby-version').strip
        else
          ruby_version = ask("What ruby version?", STRING)
        end

        if File.exists?('.env')
          append_to_file ".env", "JOB_WORKER_URL=redis://redis:6379/0"
        else
          create_file Pathname.new ".env", "JOB_WORKER_URL=redis://redis:6379/0"
        end

        DOCKERFILE = "FROM ruby:#{ruby_version}
        RUN apt-get update && apt-get install -qq -y --no-install-recommends \
              build-essential nodejs libpq-dev libqt4-dev libqtwebkit-dev
        ENV INSTALL_PATH /var/rails_app
        RUN mkdir -p $INSTALL_PATH
        WORKDIR $INSTALL_PATH
        COPY Gemfile Gemfile.lock ./
        RUN bundle install"

        dockerignore = ".git
        .dockerignore
        .byebug_history
        /log/*
        /tmp/*
        #{project}/
        /#{project}/*"

        create_file Pathname.new "Dockerfile", DOCKERFILE
        create_file Pathname.new "/#{project}/docker-compose.yml", docker_compose
        create_file Pathname.new ".dockerignore", dockerignore
      end

      def docker_compose
        file = ""
        file += "version: '2'\n"
        file += "services:"

        db = ask_menu("What database?", ["postgres", "mysql"])
        if db == "mysql"
          file += '  mysql:
              image: mysql:5.7.17
              ports:
                - "13306:3306"
              environment:
                MYSQL_ROOT_PASSWORD: root
                MYSQL_DATABASE: root
              volumes:
                - ./data/mysql:/var/lib/mysql'
        elsif db == "postgres"
          file += '  postgres:
              image: postgres:9.5
              environment:
                POSTGRES_USER: my_dockerized_app
                POSTGRES_PASSWORD: yourpassword
              ports:
                - "5432:5432"
              volumes:
                - postgres:/var/lib/postgresql/data'
        end

        redis = ask("Are you using redis? (y/n) ", ["y","n"])
        if redis == "y"
          file += '  redis:
              image: redis:3.0.7-alpine
              ports:
                - "6379:6379"
              volumes:
                - ./data/redis:/data'
        end

        sidekiq = ask("Are you using sidekiq? (y/n) ", ["y","n"])
        if sidekiq == "y"
          file += '  sidekiq:
              build: ./web
              command: bash -c "bundle exec sidekiq -C config/sidekiq.yml"
              env_file:
                - .env
              volumes:
                - ./web:/var/rails_app
              depends_on:
                - mysql
                - redis'
        end

        file += '  web:
            build: ./web
            volumes:
              - ./web:/var/rails_app
            ports:
              - "3000:3000"
            depends_on:
              - mysql
              - redis
            command: bash -c "bundle exec rails s -b 0.0.0.0"
            env_file:
              - .env'

        file
      end

      def ask(question, answer_type, &details)
        @ui.ask(@ui.color(question, :green, :bold), answer_type, &details)
      end

      def ask_menu(question, choices)
        answer = @ui.choose do |menu|
          menu.prompt = "#{@ui.color(question, :green, :bold)} "
          choices.each { |n| menu.choice(n) }
        end
        say("=> #{answer}")
        answer
      end

    end
  end
end
