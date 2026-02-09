
import sys
import uuid
import os

project_path = 'chat-storage.xcodeproj/project.pbxproj'
file_name = 'TransferModels.swift'
file_path_relative = 'chat-storage/Services/TransferModels.swift'

def generate_id():
    return uuid.uuid4().hex[:24].upper()

if not os.path.exists(project_path):
    print(f"Project file not found: {project_path}")
    sys.exit(1)

with open(project_path, 'r') as f:
    content = f.read()

if file_name in content:
    print(f"File {file_name} already exists in project")
    sys.exit(0)

print(f"Adding {file_name} to project...")

file_ref_id = generate_id()
build_file_id = generate_id()

# 1. Add PBXFileReference
# Format: 		082B4F672D4C3E2000A38289 /* TransferModels.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = TransferModels.swift; sourceTree = "<group>"; };
file_ref_entry = f'\t\t{file_ref_id} /* {file_name} */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};'

# Find insertion point (end of PBXFileReference section or after a known file)
insert_pos = content.find("/* VideoPlayerParams.swift */ = {isa = PBXFileReference")
if insert_pos == -1:
    print("Could not find anchor for FileReference")
    sys.exit(1)
    
end_of_line = content.find('\n', insert_pos)
content = content[:end_of_line+1] + file_ref_entry + '\n' + content[end_of_line+1:]

# 2. Add PBXBuildFile
# Format: 		082B4F682D4C3E2000A38289 /* TransferModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = 082B4F672D4C3E2000A38289 /* TransferModels.swift */; };
build_file_entry = f'\t\t{build_file_id} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_name} */; }};'

insert_pos = content.find("/* VideoPlayerParams.swift in Sources */ = {isa = PBXBuildFile")
if insert_pos == -1:
    print("Could not find anchor for BuildFile")
    sys.exit(1)

end_of_line = content.find('\n', insert_pos)
content = content[:end_of_line+1] + build_file_entry + '\n' + content[end_of_line+1:]

# 3. Add to Main Group (Services)
# Find Services group
services_group_start = content.find("/* Services */ = {")
if services_group_start == -1:
    print("Could not find Services group")
    sys.exit(1)

children_start = content.find("children = (", services_group_start)
if children_start == -1:
    print("Could not find children list in Services group")
    sys.exit(1)

insert_pos = content.find("\n", children_start)
group_entry = f'\t\t\t\t{file_ref_id} /* {file_name} */,'
content = content[:insert_pos+1] + group_entry + '\n' + content[insert_pos+1:]

# 4. Add to PBXSourcesBuildPhase
sources_phase_start = content.find("isa = PBXSourcesBuildPhase;")
if sources_phase_start == -1:
    print("Could not find SourcesBuildPhase")
    sys.exit(1)

files_start = content.find("files = (", sources_phase_start)
if files_start == -1:
    print("Could not find files list in SourcesBuildPhase")
    sys.exit(1)

insert_pos = content.find("\n", files_start)
# Use generated ID for build file
phase_entry = f'\t\t\t\t{build_file_id} /* {file_name} in Sources */,'
content = content[:insert_pos+1] + phase_entry + '\n' + content[insert_pos+1:]

with open(project_path, 'w') as f:
    f.write(content)

print(f"Successfully added {file_name} to project")
