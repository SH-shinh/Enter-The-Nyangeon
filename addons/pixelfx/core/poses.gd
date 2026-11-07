# The stance acts start from. A pose only says what differs from standing easy (STAND in rig.gd), in screen terms,
# px from the feet, y negative up. See src/core/poses.js for every field and how the body works.
# port-of: src/core/poses.js@c6a9daa3b945405b53d7d49ff072bb0a8499f1e8
extends RefCounted

const READY := {"crouch": 3, "fx": 11, "fy": -21, "bx": 9, "by": -21, "ffx": 7, "fbx": -7}
