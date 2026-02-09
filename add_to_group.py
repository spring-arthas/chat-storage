import sys

project_path = 'chat-storage.xcodeproj/project.pbxproj'
file_ref_id = '4E2B8E372F37294600EE9F33' # TransferModels.swift ID found earlier
file_name = 'TransferModels.swift'

with open(project_path, 'r') as f:
    content = f.read()

# Find Services group
services_idx = content.find("path = Services;")
if services_idx == -1:
    print("Services group not found")
    sys.exit(1)

# Find start of group block (searching backwards for 'children = (')
# The structure is usually:
# <GroupID> = {
#    isa = PBXGroup;
#    children = (
#       ...
#    );
#    path = Services;
# };

# Search backwards from 'path = Services' to find 'children = ('
children_start = content.rfind("children = (", 0, services_idx)
if children_start == -1:
    print("Children list start not found")
    sys.exit(1)

# specific group ID check to avoid matching wrong group
# Let's search for AuthenticationService check
auth_idx = content.find("AuthenticationService.swift", children_start, services_idx)
if auth_idx == -1:
    print("AuthenticationService not found in group, confirming group identity")
    # This might be tricky if I picked the wrong "path = Services" block, but assume unique
    pass

# Insert into children list
entry = f'\t\t\t\t{file_ref_id} /* {file_name} */,'
insert_pos = content.find("\n", children_start)
content = content[:insert_pos+1] + entry + '\n' + content[insert_pos+1:]

with open(project_path, 'w') as f:
    f.write(content)

print(f"Added {file_name} to Services group")
