require 'securerandom'

project_path = 'chat-storage.xcodeproj/project.pbxproj'
file_path = 'chat-storage/Services/TransferModels.swift'
file_name = 'TransferModels.swift'

content = File.read(project_path)

if content.include?(file_name)
  puts "File #{file_name} already exists in project"
  exit(0)
end

file_ref_id = SecureRandom.hex(12).upcase
build_file_id = SecureRandom.hex(12).upcase

# 1. PBXFileReference
# Find exist entry to insert after
insert_pos = content.index("/* VideoPlayerParams.swift */")
if insert_pos
  line_end = content.index("\n", insert_pos)
  entry = "\t\t#{file_ref_id} /* #{file_name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{file_name}; sourceTree = \"<group>\"; };"
  content.insert(line_end + 1, entry + "\n")
else
  puts "Error: Anchor for FileReference not found"
  exit(1)
end

# 2. PBXBuildFile
insert_pos = content.index("/* VideoPlayerParams.swift in Sources */")
if insert_pos
  line_end = content.index("\n", insert_pos)
  entry = "\t\t#{build_file_id} /* #{file_name} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref_id} /* #{file_name} */; };"
  content.insert(line_end + 1, entry + "\n")
else
    puts "Error: Anchor for BuildFile not found"
    exit(1)
end

# 3. PBXGroup (Services)
services_group_idx = content.index("/* Services */ = {")
if services_group_idx
  children_idx = content.index("children = (", services_group_idx)
  if children_idx
    insert_pos = content.index("\n", children_idx)
    entry = "\t\t\t\t#{file_ref_id} /* #{file_name} */,"
    content.insert(insert_pos + 1, entry + "\n")
  end
else
    puts "Error: Services group not found"
    exit(1)
end

# 4. PBXSourcesBuildPhase
sources_phase_idx = content.index("isa = PBXSourcesBuildPhase;")
if sources_phase_idx
  files_idx = content.index("files = (", sources_phase_idx)
  if files_idx
    insert_pos = content.index("\n", files_idx)
    entry = "\t\t\t\t#{build_file_id} /* #{file_name} in Sources */,"
    content.insert(insert_pos + 1, entry + "\n")
  end
else
    puts "Error: SourcesBuildPhase not found"
    exit(1)
end

File.write(project_path, content)
puts "Successfully added #{file_name} to project"
