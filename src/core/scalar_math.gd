class_name ScalarMath
extends RefCounted

# A13: this file is a deliberately closed set of pure mathematical
# identity constants (the same category as Godot's own built-in PI/TAU),
# not a general-purpose numeric constants dumping ground. src/gameplay/**
# preloads this file and references these named constants instead of a
# bare literal, which would otherwise let a numeric-laundering channel
# bypass scripts/lint_gameplay_numbers.py's src/gameplay/**-scoped scan.
# That script also checks THIS file's own literals against a frozen
# allow-list ({0.5, 2.0} exactly) -- adding or changing a constant here
# fails the lint loudly instead of silently smuggling a gameplay-affecting
# number past it. Any new gameplay-affecting number belongs in a typed
# data/tuning/*.tres resource with a real consumer, not here.
const HALF := 0.5
const DOUBLE := 2.0
