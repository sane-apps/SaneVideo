# frozen_string_literal: true

module SaneMasterModules
  # Interactive debugging workflow, app launching, logs
  module TestMode
    def launch_app(args)
      puts '🚀 --- [ SANEMASTER LAUNCH ] ---'

      dd_path = File.expand_path('~/Library/Developer/Xcode/DerivedData/SaneVideo-*/Build/Products/Debug')
      app_path = Dir.glob(File.join(dd_path, 'SaneVideo.app')).first

      unless app_path && File.exist?(app_path)
        puts '❌ App binary not found. Run ./Scripts/SaneMaster.rb verify to build.'
        return
      end

      puts "📱 Launching: #{app_path}"
      capture_logs = args.include?('--logs')
      env_vars = {}
      env_vars['VERIFY_PIP'] = ENV['VERIFY_PIP'] if ENV['VERIFY_PIP']

      if capture_logs
        puts '📝 Capturing logs to stdout...'
        pid = spawn(env_vars, "#{app_path}/Contents/MacOS/SaneVideo")
        Process.wait(pid)
      else
        system(env_vars, "open '#{app_path}'")
        puts '✅ App launched'
      end
    end

    def restore_xcode
      puts '🛠️ --- [ SANEMASTER RESTORE ] ---'
      puts 'Fixing common Xcode/Launch Services issues...'

      lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
      if File.exist?(lsregister)
        print '  Resetting Launch Services database... '
        system("#{lsregister} -kill -r -domain local -domain system -domain user")
        puts '✅'
      end

      print '  Restarting Dock... '
      system('killall Dock')
      puts '✅'

      clean(['--nuclear'])
      puts "\n✅ System restored. Try opening the project in Xcode again."
    end

    def setup_environment
      puts '🛠️ --- [ SANEMASTER SETUP ] ---'

      print '📦 Running bundle install... '
      if system('bundle install --path vendor/bundle > /dev/null 2>&1')
        puts '✅'
      else
        puts '⚠️  Bundle install failed or not needed'
      end

      print '🔍 Checking SwiftFormat... '
      puts system('which swiftformat > /dev/null 2>&1') ? '✅' : '⚠️  Not found (brew install swiftformat)'

      print '🔍 Checking SwiftLint... '
      puts system('which swiftlint > /dev/null 2>&1') ? '✅' : '⚠️  Not found (brew install swiftlint)'

      puts "\n✅ Setup complete."
    end

    def enter_test_mode(_args)
      puts '🧪 --- [ TEST MODE ] ---'
      puts 'Preparing clean testing environment...'
      puts ''

      screenshots_dir = File.join(Dir.pwd, 'Screenshots')
      log_file = File.expand_path('~/Library/Containers/com.sanevideo.SaneVideo/Data/Library/Logs/SaneVideo/SaneVideo_Debug.log')
      crash_dir = File.expand_path('~/Library/Logs/DiagnosticReports')

      kill_existing_processes
      show_screenshots(screenshots_dir)
      show_diagnostic_reports(crash_dir)
      return unless build_app

      launch_app([])
      sleep 2
      show_log_status(log_file)
      print_test_mode_ready
    end

    def show_app_logs(args)
      puts '📋 --- [ APPLICATION LOGS ] ---'

      log_file = File.expand_path('~/Library/Containers/com.sanevideo.SaneVideo/Data/Library/Logs/SaneVideo/SaneVideo_Debug.log')
      tail_count = 50
      follow_mode = args.include?('--follow') || args.include?('-f')

      args.each_with_index do |arg, i|
        tail_count = args[i + 1].to_i if arg == '--tail' && args[i + 1]
      end

      unless File.exist?(log_file)
        puts '❌ No log file found at: ~/Library/Containers/com.sanevideo.SaneVideo/Data/Library/Logs/SaneVideo/SaneVideo_Debug.log'
        puts "\nTo generate logs:"
        puts '  1. Rebuild the app: ./Scripts/SaneMaster.rb verify'
        puts '  2. Launch the app: ./Scripts/SaneMaster.rb launch'
        return
      end

      mtime = File.mtime(log_file)
      size = File.size(log_file) / 1024.0
      puts '📁 Log file: ~/Library/Containers/com.sanevideo.SaneVideo/Data/Library/Logs/SaneVideo/SaneVideo_Debug.log'
      puts "   Last updated: #{mtime.strftime('%Y-%m-%d %H:%M:%S')} (#{size.round(1)}KB)"
      puts '─' * 60

      if follow_mode
        puts 'Following log file (Ctrl+C to stop)...'
        puts ''
        # Use Kernel.exec for tail -f
        Kernel.exec("tail -f '#{log_file}'")
      else
        lines = File.readlines(log_file)
        if lines.length > tail_count
          puts "(showing last #{tail_count} of #{lines.length} lines)"
          puts ''
          puts lines.last(tail_count).join
        else
          puts lines.join
        end
      end
    end

    private

    def kill_existing_processes
      puts '1️⃣  Killing existing SaneVideo processes...'
      system('killall -9 SaneVideo 2>/dev/null')
      puts '   ✅ Done'
      puts ''
    end

    def show_screenshots(screenshots_dir)
      puts '2️⃣  Screenshots in project:'
      if Dir.exist?(screenshots_dir)
        screenshots = Dir.glob(File.join(screenshots_dir, '*.png')).sort_by { |f| File.mtime(f) }.reverse
        if screenshots.any?
          puts "   📁 #{screenshots_dir}"
          screenshots.first(5).each do |f|
            mtime = File.mtime(f).strftime('%Y-%m-%d %H:%M:%S')
            puts "   📸 #{File.basename(f)} (#{mtime})"
          end
          puts "   ... and #{screenshots.count - 5} more" if screenshots.count > 5
          puts "\n   💡 To clear old screenshots: rm Screenshots/*.png"
        else
          puts '   (no screenshots found)'
        end
      else
        puts "   (screenshots directory doesn't exist)"
      end
      puts ''
    end

    def show_diagnostic_reports(crash_dir)
      puts '3️⃣  Recent diagnostic reports:'
      crash_files = Dir.glob(File.join(crash_dir, 'SaneVideo-*.ips')).sort_by { |f| File.mtime(f) }.reverse
      hang_files = Dir.glob(File.join(crash_dir, 'SaneVideo-*.{spin,hang}')).sort_by { |f| File.mtime(f) }.reverse

      if crash_files.any?
        puts '   Crashes:'
        crash_files.first(3).each do |f|
          mtime = File.mtime(f).strftime('%Y-%m-%d %H:%M:%S')
          puts "   💥 #{File.basename(f)} (#{mtime})"
        end
        puts "   ... and #{crash_files.count - 3} more crashes" if crash_files.count > 3
      else
        puts '   💥 No crash reports'
      end

      if hang_files.any?
        puts '   Hangs/Spins:'
        hang_files.first(2).each do |f|
          mtime = File.mtime(f).strftime('%Y-%m-%d %H:%M:%S')
          puts "   🔄 #{File.basename(f)} (#{mtime})"
        end
      end

      show_xcresult_status
      puts ''
    end

    def show_xcresult_status
      xcresult_dir = File.expand_path('~/Library/Developer/Xcode/DerivedData')
      xcresults = Dir.glob(File.join(xcresult_dir, 'SaneVideo-*/Logs/Test/*.xcresult')).sort_by { |f| File.mtime(f) }.reverse
      return unless xcresults.any?

      latest = xcresults.first
      mtime = File.mtime(latest).strftime('%Y-%m-%d %H:%M:%S')
      puts "   📊 Latest test result: #{File.basename(latest)} (#{mtime})"
    end

    def build_app # rubocop:disable Naming/PredicateMethod -- performs action, not just a query
      puts '4️⃣  Building app...'
      build_success = system('xcodebuild -scheme SaneVideo -destination "platform=macOS" build 2>&1 | grep -E "(BUILD|error:)" | tail -5')
      unless build_success
        puts '   ❌ Build failed! Fix errors before continuing.'
        return false
      end
      puts '   ✅ Build succeeded'
      puts ''
      true
    end

    def show_log_status(log_file)
      puts '6️⃣  Debug log status:'
      if File.exist?(log_file)
        mtime = File.mtime(log_file).strftime('%Y-%m-%d %H:%M:%S')
        size = (File.size(log_file) / 1024.0).round(1)
        puts "   📋 #{log_file}"
        puts "   📅 Last updated: #{mtime} (#{size}KB)"
      else
        puts '   (log file not created yet - will appear after app runs)'
      end
      puts ''
    end

    def print_test_mode_ready
      puts '═' * 60
      puts '🧪 TEST MODE READY'
      puts '═' * 60
      puts ''
      puts 'Diagnostic commands:'
      puts '  ./Scripts/SaneMaster.rb logs --follow    # Watch debug log live'
      puts '  ./Scripts/SaneMaster.rb logs             # Show recent debug log'
      puts '  ./Scripts/SaneMaster.rb crashes          # Analyze crash reports'
      puts '  ./Scripts/SaneMaster.rb diagnose         # Analyze latest xcresult'
      puts ''
      puts 'All diagnostic locations:'
      puts '  📋 Debug log:    ~/Library/Containers/com.sanevideo.SaneVideo/Data/Library/Logs/SaneVideo/SaneVideo_Debug.log'
      puts '  📸 Screenshots:  Screenshots/'
      puts '  💥 Crashes:      ~/Library/Logs/DiagnosticReports/SaneVideo-*.ips'
      puts ''
      puts "  🕐 Session started: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      puts ''
      puts '⚠️  POST-FIX CHECKLIST (after each bug fix):'
      puts '  [ ] Regression test added?'
      puts '  [ ] Similar bugs checked elsewhere?'
      puts '  [ ] Changes committed to git?'
      puts '  [ ] Can explain fix in plain English?'
      puts ''
    end
  end
end
