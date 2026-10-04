package main

// run.sh and the hw_clay test gate compile the shared UI shaders into this library
// before compiling the example; the renderer never compiles shader source at runtime.
UI_METALLIB :: #load("build/ui.metallib")
