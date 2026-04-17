require 'xcodeproj'

project_path = 'chat-storage.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'chat-storage' } || project.targets.first

# Try to find or create the Views group
views_group = project.main_group.find_subpath('chat-storage/Views', true)

file_name = 'StreamingVideoPlayer.swift'
file_ref = views_group.find_file_by_path(file_name)

unless file_ref
  file_ref = views_group.new_file(file_name)
  target.add_file_references([file_ref])
  project.save
  puts "Successfully added #{file_name} to project"
else
  puts "File #{file_name} already exists in project group"
  # Make sure it's in the target
  in_target = target.source_build_phase.files.any? { |f| f.file_ref == file_ref }
  unless in_target
    target.add_file_references([file_ref])
    project.save
    puts "Added existing file ref to target"
  else
    puts "File already in target build phase"
  end
end
