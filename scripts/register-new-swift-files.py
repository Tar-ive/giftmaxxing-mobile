#!/usr/bin/env python3
"""One-shot: register ConsultView / CirclesView / PersonalizationStore in the
Xcode project (pbxproj is gitignored, so this runs locally, not in CI).
Idempotent: skips if already registered."""
import sys

P = 'Giftmaxxing.xcodeproj/project.pbxproj'
s = open(P).read()

if '5A11AA0000000000000C0501' in s:
    print('already registered — nothing to do')
    sys.exit(0)


def insert_after(anchor, addition, label):
    global s
    i = s.find(anchor)
    if i < 0:
        sys.exit(f'ANCHOR MISS: {label}')
    j = i + len(anchor)
    s = s[:j] + addition + s[j:]


# 1. PBXBuildFile entries
insert_after(
    '\t\t3842CFEC76AF552A5761F96A /* GroupGiftViews.swift in Sources */ = {isa = PBXBuildFile; fileRef = F2838920BDA08AFA84702884 /* GroupGiftViews.swift */; };\n',
    '\t\t5A11AB0000000000000C0501 /* ConsultView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A11AA0000000000000C0501 /* ConsultView.swift */; };\n'
    '\t\t5A11AE0000000000000C1BC1 /* CirclesView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A11AD0000000000000C1BC1 /* CirclesView.swift */; };\n'
    '\t\t5A11B10000000000000BE001 /* PersonalizationStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A11B00000000000000BE001 /* PersonalizationStore.swift */; };\n',
    'buildfile')

# 2. PBXFileReference entries
insert_after(
    '\t\tF2838920BDA08AFA84702884 /* GroupGiftViews.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GroupGiftViews.swift; sourceTree = "<group>"; };\n',
    '\t\t5A11AA0000000000000C0501 /* ConsultView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ConsultView.swift; sourceTree = "<group>"; };\n'
    '\t\t5A11AD0000000000000C1BC1 /* CirclesView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CirclesView.swift; sourceTree = "<group>"; };\n'
    '\t\t5A11B00000000000000BE001 /* PersonalizationStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PersonalizationStore.swift; sourceTree = "<group>"; };\n',
    'fileref')

# 3. New groups, inserted just before the Onboarding group block
anchor = '\t\tB47390A6302863026121878A /* Onboarding */ = {'
i = s.find(anchor)
if i < 0:
    sys.exit('ANCHOR MISS: group')
groups = (
    '\t\t5A11AC0000000000000C0501 /* Consult */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
    '\t\t\t\t5A11AA0000000000000C0501 /* ConsultView.swift */,\n'
    '\t\t\t);\n\t\t\tpath = Consult;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
    '\t\t5A11AF0000000000000C1BC1 /* Circles */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
    '\t\t\t\t5A11AD0000000000000C1BC1 /* CirclesView.swift */,\n'
    '\t\t\t);\n\t\t\tpath = Circles;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
)
s = s[:i] + groups + s[i:]

# 4. Views group children
insert_after(
    '\t\t\t\t5C6B424DB5BE1F6DD2D09436 /* Challenge */,\n',
    '\t\t\t\t5A11AF0000000000000C1BC1 /* Circles */,\n\t\t\t\t5A11AC0000000000000C0501 /* Consult */,\n',
    'views-children')

# 5. Services group children
insert_after(
    '\t\t\t\tF19980DDF401A5445D4CEA09 /* APIClient.swift */,\n',
    '\t\t\t\t5A11B00000000000000BE001 /* PersonalizationStore.swift */,\n',
    'services-children')

# 6. Sources build phase
insert_after(
    '\t\t\t\tEFFCFAA503B3039234B3C7FA /* APIClient.swift in Sources */,\n',
    '\t\t\t\t5A11AB0000000000000C0501 /* ConsultView.swift in Sources */,\n'
    '\t\t\t\t5A11AE0000000000000C1BC1 /* CirclesView.swift in Sources */,\n'
    '\t\t\t\t5A11B10000000000000BE001 /* PersonalizationStore.swift in Sources */,\n',
    'sources')

open(P, 'w').write(s)
print('patched ok')
