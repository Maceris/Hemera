REM Delete would be "rmdir /Q /s bin" but LLVM makes that too annoying to be default
mkdir bin
cd bin
cmake ..