# frozen_string_literal: true

# Skills Module - Manage domain-specific knowledge contexts
# Synced from SaneProcess product

module SaneMasterModules
  module Skills
    SKILLS_DIR = File.join(Dir.pwd, '.claude/skills')
    CONTEXT_FILE = File.join(Dir.pwd, '.claude/mac_context.md')
    ACTIVE_FILE = File.join(Dir.pwd, '.claude/active_skills.json')

    SKILLS_START = '<!-- SKILLS START - Auto-generated, do not edit below -->'
    SKILLS_END = '<!-- SKILLS END -->'

    # ─────────────────────────────────────────────────────────────
    # Commands
    # ─────────────────────────────────────────────────────────────

    def skill_list
      puts "\n📚 Available Skills:\n\n"

      available_skills.each do |skill|
        lines = count_skill_lines(skill[:path])
        status = active_skills.include?(skill[:name]) ? '✅' : '  '
        puts "  #{status} #{skill[:name].ljust(25)} (#{lines} lines)"
      end

      active = active_skills
      if active.any?
        puts "\n🧠 Currently loaded: #{active.join(', ')}"
      else
        puts "\n💡 No skills loaded. Use: ./Scripts/SaneMaster.rb skill load <name>"
      end
      puts
    end

    def skill_load(names)
      if names.empty?
        puts '❌ Usage: ./Scripts/SaneMaster.rb skill load <name> [name2 ...]'
        return
      end

      loaded = []
      names.each do |name|
        skill = find_skill(name)
        if skill.nil?
          puts "❌ Skill not found: #{name}"
          puts "   Available: #{available_skills.map { |s| s[:name] }.join(', ')}"
          next
        end

        if active_skills.include?(name)
          puts "⚠️  Already loaded: #{name}"
          next
        end

        add_active_skill(name)
        loaded << name
        puts "✅ Loaded: #{name} (#{count_skill_lines(skill[:path])} lines)"
      end

      return unless loaded.any?

      inject_skills_to_context
      puts "\n📝 Context updated: #{CONTEXT_FILE}"
    end

    def skill_unload(args)
      if args.include?('--all')
        clear_active_skills
        inject_skills_to_context
        puts '✅ All skills unloaded'
        return
      end

      if args.empty?
        puts '❌ Usage: ./Scripts/SaneMaster.rb skill unload <name> [--all]'
        return
      end

      args.each do |name|
        if active_skills.include?(name)
          remove_active_skill(name)
          puts "✅ Unloaded: #{name}"
        else
          puts "⚠️  Not loaded: #{name}"
        end
      end

      inject_skills_to_context
    end

    def skill_status
      active = active_skills
      if active.empty?
        puts "\n🧠 No skills currently loaded.\n\n"
        return
      end

      puts "\n🧠 Active Skills:\n\n"
      total_lines = 0

      active.each do |name|
        skill = find_skill(name)
        lines = skill ? count_skill_lines(skill[:path]) : 0
        total_lines += lines
        puts "   • #{name} (#{lines} lines)"
      end

      puts "\n   Skills added: #{total_lines} lines\n\n"
    end

    def skill_show(name)
      if name.nil?
        puts '❌ Usage: ./Scripts/SaneMaster.rb skill show <name>'
        return
      end

      skill = find_skill(name)
      if skill.nil?
        puts "❌ Skill not found: #{name}"
        return
      end

      puts "\n#{File.read(skill[:path])}\n"
    end

    # ─────────────────────────────────────────────────────────────
    # Helpers
    # ─────────────────────────────────────────────────────────────

    def available_skills
      return [] unless Dir.exist?(SKILLS_DIR)

      Dir.glob(File.join(SKILLS_DIR, '*.md')).map do |path|
        { name: File.basename(path, '.md'), path: path }
      end.sort_by { |s| s[:name] }
    end

    def find_skill(name)
      available_skills.find { |s| s[:name] == name }
    end

    def active_skills
      return [] unless File.exist?(ACTIVE_FILE)

      JSON.parse(File.read(ACTIVE_FILE))['skills'] || []
    rescue JSON::ParserError
      []
    end

    def add_active_skill(name)
      skills = active_skills
      skills << name unless skills.include?(name)
      save_active_skills(skills)
    end

    def remove_active_skill(name)
      skills = active_skills.reject { |s| s == name }
      save_active_skills(skills)
    end

    def clear_active_skills
      save_active_skills([])
    end

    def save_active_skills(skills)
      File.write(ACTIVE_FILE, JSON.pretty_generate({ skills: skills }))
    end

    def inject_skills_to_context
      return unless File.exist?(CONTEXT_FILE)

      content = File.read(CONTEXT_FILE)
      base_content = content.include?(SKILLS_START) ? content.split(SKILLS_START).first.rstrip : content

      skills = active_skills
      if skills.empty?
        File.write(CONTEXT_FILE, "#{base_content}\n")
        return
      end

      sections = [base_content, '', SKILLS_START, '', '## Loaded Skills', '']
      skills.each do |name|
        skill = find_skill(name)
        next unless skill

        sections << File.read(skill[:path])
        sections << ''
        sections << '---'
        sections << ''
      end
      sections << SKILLS_END

      File.write(CONTEXT_FILE, sections.join("\n"))
    end

    def count_skill_lines(path)
      return 0 unless File.exist?(path)

      File.read(path).lines.count
    end
  end
end
