require 'xcodeproj'

project_path = 'chat-storage.xcodeproj'
unless File.exist?(project_path)
  puts "Project not found at #{project_path}"
  exit 1
end

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'chat-storage' } || project.targets.first

puts "Target: #{target.name}"

frameworks_build_phase = target.frameworks_build_phase
if frameworks_build_phase.files.any? { |f| f.file_ref && f.file_ref.name == "AVKit.framework" }
  puts "AVKit.framework is already linked."
  exit 0
end

puts "Adding AVKit.framework to 'Link Binary With Libraries' phase..."

framework_group = project.frameworks_group
# Check if AVKit reference exists
avkit_ref = framework_group.files.find { |f| f.name == "AVKit.framework" || f.path.include?("AVKit.framework") }

unless avkit_ref
  avkit_ref = framework_group.new_reference("System/Library/Frameworks/AVKit.framework")
  avkit_ref.name = "AVKit.framework"
  avkit_ref.source_tree = 'SDKROOT'
end

frameworks_build_phase.add_file_reference(avkit_ref)
project.save

puts "Successfully added AVKit.framework to the project."
