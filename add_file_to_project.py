import sys
import uuid

project_path = 'chat-storage.xcodeproj/project.pbxproj'
file_path = 'chat-storage/Services/TransferModels.swift'
file_name = 'TransferModels.swift'

def generate_id():
    return uuid.uuid4().hex[:24].upper()

with open(project_path, 'r') as f:
    content = f.read()

if file_name in content:
    print(f"File {file_name} already exists in project")
    sys.exit(0)

file_ref_id = generate_id()
build_file_id = generate_id()

# 1. Add file reference
file_ref_entry = f'\t\t{file_ref_id} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};'
params_idx = content.find("/* VideoPlayerParams.swift */")
if params_idx != -1:
    end_of_line = content.find('\n', params_idx)
    content = content[:end_of_line+1] + file_ref_entry + '\n' + content[end_of_line+1:]
else:
    print("Could not find insertion point for file reference")
    sys.exit(1)

# 2. Add build file
build_file_entry = f'\t\t{build_file_id} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_name} */; }};'
sources_idx = content.find("/* VideoPlayerParams.swift in Sources */")
if sources_idx != -1:
    end_of_line = content.find('\n', sources_idx)
    content = content[:end_of_line+1] + build_file_entry + '\n' + content[end_of_line+1:]
else:
    print("Could not find insertion point for build file")
    sys.exit(1)

# 3. Add to main group
# Assuming "Services" group contains AuthenticationService.swift
service_group_idx = content.find("/* Services */ = {")
if service_group_idx != -1:
    children_idx = content.find("children = (", service_group_idx)
    if children_idx != -1:
        insert_idx = content.find("\n", children_idx)
        content = content[:insert_idx+1] + f'\t\t\t\t{file_ref_id} /* {file_name} */,\n' + content[insert_idx+1:]
else:
    print("Could not find Services group")
    # Fallback to main group if Services not found easily? No, better fail safely.
    sys.exit(1)

# 4. Add to Sources build phase
# We already added the PBXBuildFile entry, but need to add it to the PBXSourcesBuildPhase
sources_phase_idx = content.find("isa = PBXSourcesBuildPhase;")
if sources_phase_idx != -1:
    files_idx = content.find("files = (", sources_phase_idx)
    if files_idx != -1:
         insert_idx = content.find("\n", files_idx)
         content = content[:insert_idx+1] + f'\t\t\t\t{build_file_id} /* {file_name} in Sources */,\n' + content[insert_idx+1:]

with open(project_path, 'w') as f:
    f.write(content)

print(f"Successfully added {file_name} to project")
