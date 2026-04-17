require 'xcodeproj'

project_path = 'chat-storage.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'chat-storage' } || project.targets.first

file_path = 'chat-storage/Services/VideoWindowManager.swift'
group_path = 'chat-storage/Services'

group = project.main_group.find_subpath(group_path, true)
file_ref = group.find_file_by_path(File.basename(file_path))

unless file_ref
  file_ref = group.new_file(File.basename(file_path))
  target.add_file_references([file_ref])
  project.save
  puts "Successfully added #{file_path} to project"
else
  puts "File #{file_path} already exists in project"
end
