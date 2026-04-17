require 'xcodeproj'

project_path = 'chat-storage.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'chat-storage' } || project.targets.first

# Remove wrongly-added file refs first
all_refs = project.main_group.recursive_children.select { |c| c.respond_to?(:path) && c.path == 'StreamingVideoPlayer.swift' }
puts "Found #{all_refs.count} refs with path 'StreamingVideoPlayer.swift'"
all_refs.each do |ref|
  puts "  Parent: #{ref.parent.hierarchy_path}, Path: #{ref.real_path rescue 'unknown'}"
end

# Remove from target build phase if pointing to wrong location
wrong_refs = all_refs.select { |ref| ref.parent.hierarchy_path.to_s !~ /Views/ }
wrong_refs.each do |ref|
  puts "  Removing wrong ref from parent #{ref.parent.hierarchy_path}"
  target.source_build_phase.files.select { |f| f.file_ref == ref }.each(&:remove_from_project)
  ref.remove_from_project
end

project.save
puts "\nNow adding correct ref..."

# Find or create the Views group
main_group = project.main_group
app_group = main_group.find_subpath('chat-storage', false)
views_group = app_group&.find_subpath('Views', false)

if views_group.nil?
  puts "Views group not found, trying an alternative lookup..."
  app_group&.children&.each { |c| puts "child: #{c.path rescue 'no-path'} #{c.class}" }
  exit 1
end

puts "Views group found: #{views_group.hierarchy_path}"

file_ref = views_group.find_file_by_path('StreamingVideoPlayer.swift')
if file_ref.nil?
  file_ref = views_group.new_file('StreamingVideoPlayer.swift')
  puts "Created new file ref"
else
  puts "File ref already exists"
end

in_target = target.source_build_phase.files.any? { |f| f.file_ref == file_ref }
unless in_target
  target.add_file_references([file_ref])
  puts "Added file ref to target"
end

project.save
puts "Done. Real path: #{file_ref.real_path rescue 'N/A'}"
