class_name PlayerFrameDecision
extends RefCounted

const IMPULSE_NONE := &"none"
const IMPULSE_JUMP := &"jump"
const IMPULSE_DOUBLE_JUMP := &"double_jump"
const IMPULSE_HIGH_JUMP := &"high_jump"
const IMPULSE_SLIDE_JUMP := &"slide_jump"
const IMPULSE_BODY_SLAM := &"body_slam"

var impulse := IMPULSE_NONE
var previous_state := &""
var state := &""
var landed: bool
var spin_started: bool
var spin_ended: bool
