# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # reveals the status of an object based on the lifecycles
      class Status
        # verbiage we want to use to describe an item when it has completed a particular step
        STATUS_CODE_DISP_TXT = {
          0 => 'Unknown Status', # if there are no milestones for the current version, someone likely messed up the versioning process.
          1 => 'Registered',
          2 => 'In accessioning',
          3 => 'In accessioning (described)',
          4 => 'In accessioning (described, published)',
          5 => 'In accessioning (described, published, deposited)',
          6 => 'Accessioned',
          7 => 'Accessioned (indexed)',
          8 => 'Accessioned (indexed, ingested)',
          9 => 'Opened'
        }.freeze

        # milestones from accessioning and the order they happen in
        STEPS = {
          'registered' => 1,
          'submitted' => 2,
          'described' => 3,
          'published' => 4,
          'deposited' => 5,
          'accessioned' => 6,
          'indexed' => 7,
          'shelved' => 8,
          'opened' => 9
        }.freeze

        # @param [String] druid the object identifier
        # @param [String] version the version identifier
        # @param [LifecycleRoutes] lifecycle_routes the lifecycle client
        def initialize(druid:, version:, lifecycle_routes:)
          @druid = druid
          @version = version
          @lifecycle_routes = lifecycle_routes
        end

        # @return [Hash{Symbol => Object}] including :status_code and :status_time
        # rubocop:disable Metrics/MethodLength
        def info
          @info ||= begin
            # if we have an accessioned milestone, this is the last possible step and should be the status regardless of time stamp
            accessioned_milestones = current_milestones.select { |m| m[:milestone] == 'accessioned' }
            return { status_code: STEPS['accessioned'], status_time: accessioned_milestones.last[:at].utc.xmlschema } unless accessioned_milestones.empty?

            status_code = 0
            status_time = nil
            # for each milestone in the current version, see if it comes at the same time or after the current 'last' step, if so, make it the last and record the date/time
            current_milestones.each do |m|
              m_name = m[:milestone]
              m_time = m[:at].utc.xmlschema
              next unless STEPS.key?(m_name) && (!status_time || m_time >= status_time)

              status_code = STEPS[m_name]
              status_time = m_time
            end

            { status_code: status_code, status_time: status_time }
          end
        end
        # rubocop:enable Metrics/MethodLength

        def status_code
          info.fetch(:status_code)
        end

        # @param [Boolean] include_time
        # @return [String] single composed status from status_info
        def display(include_time: false)
          status_time = info[:status_time]

          # use the translation table to get the appropriate verbage for the latest step
          result = "v#{version} #{STATUS_CODE_DISP_TXT[status_code]}"
          result += " #{format_date(status_time)}" if include_time
          result
        end

        def display_simplified
          simplified_status_code(STATUS_CODE_DISP_TXT[status_code])
        end

        def milestones
          @milestones ||= lifecycle_routes.milestones(druid: druid)
        end

        private

        attr_reader :druid, :version, :lifecycle_routes

        # @return [String] text translation of the status code, minus any trailing parenthetical explanation
        # e.g. 'In accessioning (described)' and 'In accessioning (described, published)' both return 'In accessioning'
        def simplified_status_code(display)
          display.gsub(/\(.*\)$/, '').strip
        end

        def current_milestones
          current = []
          # only get steps that are part of accessioning and part of the current version. That can mean they were archived with the current version
          # number, or they might be active (no version number).
          milestones.each do |m|
            if STEPS.key?(m[:milestone]) && (m[:version].nil? || m[:version] == version)
              current << m unless m[:milestone] == 'registered' && version.to_i > 1
            end
          end
          current
        end

        # handles formating utc date/time to human readable
        # XXX: bad form to hardcode TZ here.
        def format_date(datetime)
          d =
            if datetime.is_a?(Time)
              datetime
            else
              DateTime.parse(datetime).in_time_zone(ActiveSupport::TimeZone.new('Pacific Time (US & Canada)'))
            end
          I18n.l(d).strftime('%Y-%m-%d %I:%M%p')
        rescue StandardError
          d = datetime.is_a?(Time) ? datetime : Time.parse(datetime.to_s)
          d.strftime('%Y-%m-%d %I:%M%p')
        end
      end
    end
  end
end
