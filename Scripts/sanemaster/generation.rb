# frozen_string_literal: true

module SaneMasterModules
  # Code generation: tests, mocks, templates, assets, API verification
  module Generation
    include Base

    def manage_templates(args)
      ensure_template_dir
      subcommand = args.shift || 'list'

      case subcommand
      when 'save' then save_template(args.first || 'default')
      when 'apply' then apply_template(args.first || 'default')
      when 'list' then list_templates
      when 'delete' then delete_template(args.first)
      else
        puts "Unknown template command: #{subcommand}"
        puts 'Usage: template [save|apply|list|delete] [name]'
      end
    end

    def generate_test_assets
      puts '🎬 --- [ SANEMASTER TEST ASSETS ] ---'
      puts 'Generating lightweight test media...'

      assets_dir = 'Tests/Assets'
      FileUtils.mkdir_p(assets_dir)

      unless system('which ffmpeg > /dev/null 2>&1')
        puts '❌ ffmpeg not found. Install: brew install ffmpeg'
        return
      end

      generate_test_video(assets_dir)
      generate_silence_audio(assets_dir)
      puts "\n✅ Test assets ready."
    end

    def generate_test_file(args)
      puts '🧪 --- [ SANEMASTER TEST GENERATOR ] ---'

      if args.empty?
        print_test_generator_help
        return
      end

      test_name = args.shift
      options = parse_test_options(args)

      test_dir = options[:type] == 'ui' ? 'SaneVideoUITests' : 'SaneVideoTests'
      test_file = "#{test_dir}/#{test_name}.swift"

      if File.exist?(test_file)
        puts "⚠️  File already exists: #{test_file}"
        print 'Overwrite? (y/N): '
        return unless $stdin.gets.chomp.downcase == 'y'
      end

      content = generate_test_content(test_name, options)
      File.write(test_file, content)

      puts "✅ Created: #{test_file}"
      puts "\n📝 Next steps:"
      puts '  1. Review the generated test template'
      puts '  2. Add your test cases following AAA pattern (Arrange-Act-Assert)'
      puts '  3. Run: ./Scripts/SaneMaster.rb verify'
    end

    def generate_mocks(args)
      puts '🎭 --- [ SANEMASTER MOCK GENERATOR ] ---'

      unless system('which mockolo > /dev/null 2>&1')
        puts '❌ Mockolo not found.'
        puts "\nInstall Mockolo:"
        puts '  brew install mockolo'
        return
      end

      if args.empty?
        print_mock_generator_help
        return
      end

      target, protocol, output_dir = parse_mock_options(args)
      FileUtils.mkdir_p(output_dir)
      output_file = File.join(output_dir, 'Mocks.swift')

      if target
        generate_mocks_for_target(target, output_file, output_dir)
      elsif protocol
        generate_mock_for_protocol(protocol, output_file, output_dir)
      else
        puts '❌ Must specify --target or --protocol'
      end
    end

    def check_xcodegen(files)
      return if files.empty?

      project_path = File.expand_path('SaneVideo.xcodeproj', Dir.pwd)
      unless File.exist?(project_path)
        puts "❌ Project file not found. Run 'xcodegen generate' first."
        exit 1
      end

      begin
        require 'xcodeproj'
      rescue LoadError
        puts '⚠️  Skipping XcodeGen check (run with: bundle exec ./Scripts/SaneMaster.rb)'
        return
      end

      project_files = collect_project_files(project_path)
      missing_files = find_missing_files(files, project_files)

      if missing_files.any?
        puts '❌ New Swift files not in Xcode project:'
        missing_files.each { |f| puts "   - #{f}" }
        puts "\n💡 Run: xcodegen generate"
        exit 1
      end

      exit 0
    end

    def verify_api(args)
      if args.empty?
        print_verify_api_help
        return
      end

      api_name = args[0]
      framework = args[1] || 'auto'

      puts '🔍 --- [ SDK API VERIFICATION ] ---'
      puts "Searching for: #{api_name}"
      puts "Framework: #{framework == 'auto' ? 'auto-detect' : framework}"
      puts ''

      sdk_path, sdk_version = find_sdk
      return unless sdk_path

      puts "📦 Using SDK: #{sdk_version}"
      puts ''

      frameworks_to_search = framework == 'auto' ? default_frameworks : [framework]
      found = search_frameworks_for_api(sdk_path, frameworks_to_search, api_name)

      print_api_not_found(api_name) unless found
    end

    def verify_mocks
      puts '🎭 --- [ MOCK SYNCHRONIZATION CHECK ] ---'

      unless system('which mockolo > /dev/null 2>&1')
        puts '❌ Mockolo not found. Install: brew install mockolo'
        return
      end

      puts '📂 Scanning for @mockable protocols...'
      protocol_files = `find SaneVideo -name "*.swift" -exec grep -l "@mockable" {} \\;`.strip.split("\n")

      if protocol_files.empty?
        puts '⚠️  No @mockable protocols found'
        return
      end

      puts "   Found #{protocol_files.length} protocol(s) with @mockable"
      puts ''

      mocks_file = 'SaneVideoTests/Mocks/Mocks.swift'
      unless File.exist?(mocks_file)
        puts "❌ Mocks file not found: #{mocks_file}"
        puts '   Run: ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
        return
      end

      compare_mocks(mocks_file)
    end

    def check_protocol_changes(files)
      return if files.empty?

      protocol_files = files.select do |file|
        file.include?('Protocol') && file.end_with?('.swift') && File.exist?(file)
      end
      return if protocol_files.empty?

      changed_mockable = protocol_files.select do |file|
        content = File.read(file)
        content.include?('@mockable') || content.include?('protocol')
      end
      return unless changed_mockable.any?

      puts "\n⚠️  Protocol files with @mockable were modified:"
      changed_mockable.each { |f| puts "   - #{f}" }
      puts "\n💡 Remember to regenerate mocks:"
      puts '   ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
      puts "\n   (This is a reminder - commit will proceed)"
    end

    def verify_documentation_sync
      puts '📚 --- [ DOCUMENTATION SYNC CHECK ] ---'

      issues = []
      dev_doc = File.read('DEVELOPMENT.md')
      help_output = `./Scripts/SaneMaster.rb 2>&1`

      commands_in_help = help_output.scan(/^\s+(\w+)/).flatten.uniq
      commands_in_help.reject! { |c| %w[Examples: Commands: console check_xcodegen check_protocol_changes].include?(c) }

      commands_in_help.each do |cmd|
        issues << "Command '#{cmd}' exists in SaneMaster but not documented in DEVELOPMENT.md" unless dev_doc.include?(cmd) || dev_doc.include?("`#{cmd}`")
      end

      check_documentation_flags(dev_doc, issues)

      if issues.empty?
        puts '✅ Documentation is in sync with tools'
      else
        puts '⚠️  Documentation drift detected:'
        issues.each { |issue| puts "   - #{issue}" }
        puts "\n💡 Update DEVELOPMENT.md to reflect current tool capabilities"
      end

      issues.any?
    end

    private

    def ensure_template_dir
      FileUtils.mkdir_p(TEMPLATE_DIR)
    end

    def save_template(name)
      puts "📦 --- [ SAVE TEMPLATE: #{name} ] ---"

      template_path = File.join(TEMPLATE_DIR, name)
      FileUtils.mkdir_p(template_path)

      template_files = {
        'Gemfile' => 'Gemfile',
        '.ruby-version' => '.ruby-version',
        '.swiftlint.yml' => '.swiftlint.yml',
        'project.yml' => 'project.yml',
        '.mcp.json' => '.mcp.json',
        'lefthook.yml' => 'lefthook.yml',
        '.claude/settings.json' => '.claude/settings.json'
      }

      saved = copy_template_files(template_files, template_path)
      save_template_metadata(name, template_path, saved)

      puts "✅ Template saved: #{template_path}"
      puts "   Files: #{saved.join(', ')}"
      puts "\n💡 Apply to new project: ./Scripts/SaneMaster.rb template apply #{name}"
    end

    def copy_template_files(template_files, template_path)
      saved = []
      template_files.each do |src, dest|
        src_path = File.join(Dir.pwd, src)
        next unless File.exist?(src_path)

        dest_path = File.join(template_path, dest)
        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(src_path, dest_path)
        saved << src
      end
      saved
    end

    def save_template_metadata(name, template_path, saved)
      metadata = {
        name: name,
        created_at: Time.now.iso8601,
        source_project: File.basename(Dir.pwd),
        files: saved
      }
      File.write(File.join(template_path, 'metadata.json'), JSON.pretty_generate(metadata))
    end

    def apply_template(name)
      puts "📥 --- [ APPLY TEMPLATE: #{name} ] ---"

      template_path = File.join(TEMPLATE_DIR, name)
      unless File.exist?(template_path)
        puts "❌ Template not found: #{name}"
        list_templates
        return
      end

      show_template_metadata(template_path)
      applied = apply_template_files(template_path)

      if applied.any?
        puts "\n✅ Applied files:"
        applied.each { |f| puts "   - #{f}" }
        puts "\n💡 Run ./Scripts/SaneMaster.rb bootstrap to complete setup"
      else
        puts '⚠️  No new files applied (all exist already)'
      end
    end

    def show_template_metadata(template_path)
      metadata_file = File.join(template_path, 'metadata.json')
      return unless File.exist?(metadata_file)

      metadata = JSON.parse(File.read(metadata_file))
      puts "📋 Template from: #{metadata['source_project']} (#{metadata['created_at']})"
    end

    def apply_template_files(template_path)
      applied = []
      Dir.glob(File.join(template_path, '**/*')).each do |src|
        next if File.directory?(src)
        next if src.end_with?('metadata.json')

        relative = src.sub("#{template_path}/", '')
        dest = File.join(Dir.pwd, relative)

        if File.exist?(dest)
          puts "   ⚠️  Skipping (exists): #{relative}"
          next
        end

        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
        applied << relative
      end
      applied
    end

    def list_templates
      puts '📋 --- [ AVAILABLE TEMPLATES ] ---'

      templates = Dir.glob(File.join(TEMPLATE_DIR, '*')).select { |f| File.directory?(f) }

      if templates.empty?
        puts '   No templates saved yet.'
        puts "\n💡 Save current project as template: ./Scripts/SaneMaster.rb template save mytemplate"
        return
      end

      templates.each { |template_path| display_template(template_path) }
    end

    def display_template(template_path)
      name = File.basename(template_path)
      metadata_file = File.join(template_path, 'metadata.json')

      if File.exist?(metadata_file)
        metadata = JSON.parse(File.read(metadata_file))
        puts "   #{name}"
        puts "      From: #{metadata['source_project']}"
        puts "      Created: #{metadata['created_at']}"
        puts "      Files: #{metadata['files']&.count || '?'}"
      else
        puts "   #{name} (no metadata)"
      end
      puts ''
    end

    def delete_template(name)
      return puts '❌ Specify template name to delete' unless name

      template_path = File.join(TEMPLATE_DIR, name)
      unless File.exist?(template_path)
        puts "❌ Template not found: #{name}"
        return
      end

      FileUtils.rm_rf(template_path)
      puts "✅ Deleted template: #{name}"
    end

    def generate_test_video(assets_dir)
      video_path = "#{assets_dir}/test_video.mp4"
      if File.exist?(video_path)
        puts '  ⚠️  test_video.mp4 already exists, skipping'
        return
      end

      print '  Generating test_video.mp4 (5s, 640x480)... '
      cmd = "ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p -y #{video_path} 2>/dev/null"
      puts system(cmd) ? '✅' : '❌ Failed'
    end

    def generate_silence_audio(assets_dir)
      silence_path = "#{assets_dir}/test_silence.mp4"
      if File.exist?(silence_path)
        puts '  ⚠️  test_silence.mp4 already exists, skipping'
        return
      end

      print '  Generating test_silence.mp4 (5s silence)... '
      cmd = "ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -c:a aac -y #{silence_path} 2>/dev/null"
      puts system(cmd) ? '✅' : '❌ Failed'
    end

    def print_test_generator_help
      puts 'Usage: ./Scripts/SaneMaster.rb gen_test <test_name> [options]'
      puts ''
      puts 'Options:'
      puts '  --type <unit|ui>     Test type (default: unit)'
      puts '  --framework <xctest|testing>  Framework (default: testing)'
      puts '  --target <class>     Target class/service to test'
      puts '  --async              Include async/await patterns'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb gen_test MyFeatureTests --target MyFeature'
      puts '  ./Scripts/SaneMaster.rb gen_test MyUITests --type ui --framework xctest'
    end

    def parse_test_options(args)
      options = { type: 'unit', framework: 'testing', target: nil, async: false }

      args.each_with_index do |arg, i|
        case arg
        when '--type' then options[:type] = args[i + 1] if args[i + 1]
        when '--framework' then options[:framework] = args[i + 1] if args[i + 1]
        when '--target' then options[:target] = args[i + 1] if args[i + 1]
        when '--async' then options[:async] = true
        end
      end

      options
    end

    def generate_test_content(test_name, options)
      if options[:framework] == 'xctest'
        generate_xctest_content(test_name, options)
      else
        generate_testing_framework_content(test_name, options)
      end
    end

    def generate_xctest_content(test_name, options)
      target_class = options[:target] || 'TargetClass'
      async_suffix = options[:async] ? ' async throws' : ''
      await_prefix = options[:async] ? 'await ' : ''
      timeout = options[:type] == 'ui' ? '300.0' : '60.0'
      timeout_comment = options[:type] == 'ui' ? '5 minutes' : '1 minute'

      <<~SWIFT
        //
        //  #{test_name}.swift
        //  #{options[:type] == 'ui' ? 'SaneVideoUITests' : 'SaneVideoTests'}
        //
        //  Generated by SaneMaster.rb test generator
        //  Follow AAA pattern: Arrange-Act-Assert
        //

        import XCTest
        #{'import XCUITest' if options[:type] == 'ui'}
        #{'import AVFoundation' if options[:async]}
        @testable import SaneVideo

        @MainActor
        final class #{test_name}: XCTestCase {

            // MARK: - Test Setup

            var sut: #{target_class}!

            override func setUpWithError() throws {
                continueAfterFailure = false

                if #available(macOS 13.0, *) {
                    executionTimeAllowance = #{timeout} // #{timeout_comment} max per test
                }

                sut = #{target_class}()
            }

            override func tearDownWithError() throws {
                sut = nil
            }

            // MARK: - Test Cases

            func testInitialState()#{async_suffix} {
                // Arrange - (Setup is done in setUp)

                // Act
                // TODO: Replace with actual behavior verification

                // Assert
                XCTAssertNotNil(sut, "SUT should be initialized")
            }

            func testBasicFunctionality()#{async_suffix} {
                // Arrange
                let expectedValue = "expected"

                // Act
                #{await_prefix}let result = sut.someMethod()

                // Assert
                XCTAssertEqual(result, expectedValue, "Result should match expected value")
            }
        }
      SWIFT
    end

    def generate_testing_framework_content(test_name, options)
      target_class = options[:target] || 'TargetClass'
      async_suffix = options[:async] ? ' async throws' : ''
      await_prefix = options[:async] ? 'await ' : ''

      <<~SWIFT
        //
        //  #{test_name}.swift
        //  #{options[:type] == 'ui' ? 'SaneVideoUITests' : 'SaneVideoTests'}
        //
        //  Generated by SaneMaster.rb test generator
        //  Follow AAA pattern: Arrange-Act-Assert
        //

        import Testing
        #{'import AVFoundation' if options[:async]}
        @testable import SaneVideo

        @Suite("#{test_name.gsub(/([A-Z])/, ' \\1').strip} Tests")
        @MainActor
        struct #{test_name} {

            var sut: #{target_class} { #{target_class}() }

            @Test("Initial state verification")
            func initialState()#{async_suffix} {
                let systemUnderTest = sut
                #expect(systemUnderTest != nil)
            }

            @Test("Basic functionality")
            func basicFunctionality()#{async_suffix} {
                let expectedValue = "expected"
                #{await_prefix}let result = sut.someMethod()
                #expect(result == expectedValue)
            }
        }
      SWIFT
    end

    def print_mock_generator_help
      puts 'Usage: ./Scripts/SaneMaster.rb gen_mock [options]'
      puts ''
      puts 'Options:'
      puts '  --target <dir>        Generate mocks for all protocols in directory'
      puts '  --protocol <name>     Generate mock for specific protocol'
      puts '  --output <dir>        Output directory (default: SaneVideoTests/Mocks)'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb gen_mock --target Services/Camera'
      puts '  ./Scripts/SaneMaster.rb gen_mock --protocol CameraServiceProtocol'
    end

    def parse_mock_options(args)
      target = nil
      protocol = nil
      output_dir = 'SaneVideoTests/Mocks'

      args.each_with_index do |arg, i|
        case arg
        when '--target' then target = args[i + 1] if args[i + 1]
        when '--protocol' then protocol = args[i + 1] if args[i + 1]
        when '--output' then output_dir = args[i + 1] if args[i + 1]
        end
      end

      [target, protocol, output_dir]
    end

    def generate_mocks_for_target(target, output_file, output_dir)
      puts "Generating mocks for target: #{target}"
      source_dir = "SaneVideo/#{target}"
      unless File.directory?(source_dir)
        puts "❌ Directory not found: #{source_dir}"
        return
      end

      cmd = "mockolo -s #{source_dir} -d #{output_file} --enable-args-history --mock-all"
      puts "Running: #{cmd}"

      if system(cmd)
        post_process_mocks(output_file)
        puts '✅ Mocks generated successfully'
        print_mock_next_steps(output_dir)
      else
        puts '❌ Mock generation failed'
      end
    end

    def generate_mock_for_protocol(protocol, output_file, output_dir)
      puts "Generating mock for protocol: #{protocol}"
      protocol_file = `find SaneVideo -name "*.swift" -exec grep -l "protocol #{protocol}" {} \\;`.strip

      if protocol_file.empty?
        puts "❌ Protocol not found: #{protocol}"
        return
      end

      protocol_dir = File.dirname(protocol_file)
      cmd = "mockolo -s #{protocol_dir} -d #{output_file} --enable-args-history --mock-all -i #{protocol}"
      puts "Running: #{cmd}"

      if system(cmd)
        post_process_mocks(output_file)
        puts '✅ Mocks generated successfully'
        print_mock_next_steps(output_dir)
      else
        puts '❌ Mock generation failed'
      end
    end

    def post_process_mocks(output_file)
      return unless File.exist?(output_file)

      content = File.read(output_file)
      content.gsub!(/^import [A-Za-z]+ [A-Za-z]+.*\n/, '')
      content.gsub!(/(import Foundation\n)/, "\\1@testable import SaneVideo\n") unless content.include?('@testable import SaneVideo')
      File.write(output_file, content)
    end

    def print_mock_next_steps(output_dir)
      puts "\n✅ Mocks generated in: #{output_dir}"
      puts "\n📝 Next steps:"
      puts '  1. Review generated mocks'
      puts '  2. Import in your test files'
      puts '  3. Use in tests: let mock = MockCameraService()'
    end

    def collect_project_files(project_path)
      require 'xcodeproj'
      project = Xcodeproj::Project.open(project_path)
      project_files = Set.new

      project.files.each do |file|
        next unless file.path&.end_with?('.swift')

        path = file.path
        project_files.add(path)
        project_files.add(path.sub(%r{^SaneVideo/}, ''))
        project_files.add("SaneVideo/#{path}") unless path.start_with?('SaneVideo/')
      end

      project_files
    end

    def find_missing_files(files, project_files)
      missing = []
      files.each do |file|
        next unless file.end_with?('.swift')
        next if file.include?('Test')

        is_new = `git diff --cached --diff-filter=A --name-only -- "#{file}" 2>/dev/null`.strip == file
        next unless is_new

        normalized = file.start_with?('SaneVideo/') ? file : "SaneVideo/#{file}"
        path_without_prefix = file.sub(%r{^SaneVideo/}, '')

        missing << file unless project_files.include?(file) || project_files.include?(normalized) || project_files.include?(path_without_prefix)
      end
      missing
    end

    def print_verify_api_help
      puts 'Usage: ./Scripts/SaneMaster.rb verify_api <APIName> [Framework]'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision'
      puts '  ./Scripts/SaneMaster.rb verify_api SCContentSharingPicker ScreenCaptureKit'
    end

    def find_sdk
      sdk_base = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs'
      sdks = Dir.glob("#{sdk_base}/MacOSX*.sdk").sort.reverse

      if sdks.empty?
        puts '❌ No macOS SDK found. Is Xcode installed?'
        return nil
      end

      sdk_path = sdks.first
      sdk_version = File.basename(sdk_path).gsub('MacOSX', '').gsub('.sdk', '')
      [sdk_path, sdk_version]
    end

    def default_frameworks
      %w[Vision AVFoundation ScreenCaptureKit Foundation AppKit SwiftUI CoreMedia]
    end

    def search_frameworks_for_api(sdk_path, frameworks, api_name)
      found = false
      frameworks.each do |fw|
        framework_path = "#{sdk_path}/System/Library/Frameworks/#{fw}.framework"
        next unless File.exist?(framework_path)

        swiftinterface_files = Dir.glob("#{framework_path}/**/*.swiftinterface")
        next if swiftinterface_files.empty?

        swiftinterface_files.each do |swift_file|
          result = `grep -n "#{api_name}" "#{swift_file}" 2>/dev/null`
          next if result.empty?

          found = true
          display_api_match(fw, swift_file, api_name, result)
        end
      end
      found
    end

    def display_api_match(framework, swift_file, api_name, result)
      puts "✅ Found in #{framework}:"
      puts "   File: #{File.basename(swift_file)}"
      puts ''

      lines = result.split("\n").first(3)
      lines.each do |line|
        line_num = line.split(':').first
        context = `sed -n '#{[line_num.to_i - 2, 1].max},#{line_num.to_i + 5}p' "#{swift_file}" 2>/dev/null`
        puts "   Line #{line_num}:"
        context.split("\n").each do |ctx_line|
          prefix = ctx_line.include?(api_name) ? '   >>> ' : '      '
          puts "#{prefix}#{ctx_line.strip}"
        end
        puts ''
      end
    end

    def print_api_not_found(api_name)
      puts "❌ API '#{api_name}' not found in SDK"
      puts ''
      puts '💡 Tips:'
      puts '   - Check spelling (case-sensitive)'
      puts '   - Try searching for partial name'
      puts '   - Framework may be different - try without framework to search all'
    end

    def compare_mocks(mocks_file)
      puts '🔄 Generating temporary mocks for comparison...'
      temp_dir = Dir.mktmpdir
      temp_mocks = File.join(temp_dir, 'Mocks.swift')

      cmd = "mockolo -s SaneVideo/Core/Protocols -d #{temp_mocks} --enable-args-history --mock-all 2>/dev/null"
      unless system(cmd)
        puts '❌ Failed to generate temporary mocks'
        FileUtils.rm_rf(temp_dir)
        return
      end

      post_process_mocks(temp_mocks) if File.exist?(temp_mocks)

      existing_protocols = File.read(mocks_file).scan(/class (\w+ProtocolMock)/).flatten
      temp_protocols = File.read(temp_mocks).scan(/class (\w+ProtocolMock)/).flatten

      missing = temp_protocols - existing_protocols
      extra = existing_protocols - temp_protocols

      FileUtils.rm_rf(temp_dir)

      if missing.empty? && extra.empty?
        puts '✅ Mocks are synchronized with protocols'
      else
        puts '⚠️  Mocks may be out of sync:'
        puts "   Missing mocks: #{missing.join(', ')}" if missing.any?
        puts "   Extra mocks: #{extra.join(', ')}" if extra.any?
        puts "\n💡 Regenerate mocks: ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols"
      end
    end

    def check_documentation_flags(dev_doc, issues)
      issues << "DEVELOPMENT.md doesn't mention --ui flag for verify command" unless dev_doc.include?('verify --ui') || dev_doc.include?('--ui')
      issues << 'SDK API verification tool (verify_api) not documented' unless dev_doc.include?('verify_api') || dev_doc.include?('SDK API verification')
      return if dev_doc.include?('verify_mocks') || dev_doc.include?('mock synchronization')

      issues << 'Mock synchronization check (verify_mocks) not documented'
    end
  end
end
