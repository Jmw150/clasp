opt -strip-debug clasp.bc -o clasp.stripped.bc
"clang++" \
    clasp.stripped.bc -flto -Wl,-lto_library,/Users/meister/Development/externals-clasp/build/release/lib/libLTO.dylib,-save-temps \
    -Wl,-mllvm,-disable-llvm-verifier \
-o "clasp-clang-lto" \
"-L/usr/local/Cellar/gmp/6.0.0a/lib" \
-L/Users/meister/Development/externals-clasp/build/release/lib \
-lLLVMLTO \
-lLLVMObjCARCOpts \
-lLLVMSymbolize \
-lLLVMDebugInfoPDB \
-lLLVMDebugInfoDWARF \
-lLLVMMIRParser \
-lLLVMLibDriver \
-lLLVMOption \
-lLLVMTableGen \
-lLLVMOrcJIT \
-lLLVMPasses \
-lLLVMipo \
-lLLVMVectorize \
-lLLVMLinker \
-lLLVMIRReader \
-lLLVMAsmParser \
-lLLVMX86Disassembler \
-lLLVMX86AsmParser \
-lLLVMX86CodeGen \
-lLLVMSelectionDAG \
-lLLVMAsmPrinter \
-lLLVMX86Desc \
-lLLVMMCDisassembler \
-lLLVMX86Info \
-lLLVMX86AsmPrinter \
-lLLVMX86Utils \
-lLLVMMCJIT \
-lLLVMLineEditor \
-lLLVMDebugInfoCodeView \
-lLLVMInterpreter \
-lLLVMExecutionEngine \
-lLLVMRuntimeDyld \
-lLLVMCodeGen \
-lLLVMTarget \
-lLLVMScalarOpts \
-lLLVMInstCombine \
-lLLVMInstrumentation \
-lLLVMProfileData \
-lLLVMObject \
-lLLVMMCParser \
-lLLVMTransformUtils \
-lLLVMMC \
-lLLVMBitWriter \
-lLLVMBitReader \
-lLLVMAnalysis \
-lLLVMCore \
-lLLVMSupport \
-lz \
-lpthread \
-ledit \
-lcurses \
-lm \
 \
-L/usr/local/Cellar/gmp/6.0.0a/lib \
-L/opt/local/lib \
-L/usr/lib \
-Wl,-object_path_lto,clasp.lto.o \
-Wl,-stack_size,0x1000000 \
-fvisibility=default \
-lc++ \
-lto_library \
/Users/meister/Development/externals-clasp/build/release/lib/libLTO.dylib \
-rdynamic \
-stdlib=libc++ \
"-L/usr/local/Cellar/gmp/6.0.0a/lib" \
-L/Users/meister/Development/externals-clasp/build/release/lib \
-lLLVMLTO \
-lLLVMObjCARCOpts \
-lLLVMSymbolize \
-lLLVMDebugInfoPDB \
-lLLVMDebugInfoDWARF \
-lLLVMMIRParser \
-lLLVMLibDriver \
-lLLVMOption \
-lLLVMTableGen \
-lLLVMOrcJIT \
-lLLVMPasses \
-lLLVMipo \
-lLLVMVectorize \
-lLLVMLinker \
-lLLVMIRReader \
-lLLVMAsmParser \
-lLLVMX86Disassembler \
-lLLVMX86AsmParser \
-lLLVMX86CodeGen \
-lLLVMSelectionDAG \
-lLLVMAsmPrinter \
-lLLVMX86Desc \
-lLLVMMCDisassembler \
-lLLVMX86Info \
-lLLVMX86AsmPrinter \
-lLLVMX86Utils \
-lLLVMMCJIT \
-lLLVMLineEditor \
-lLLVMDebugInfoCodeView \
-lLLVMInterpreter \
-lLLVMExecutionEngine \
-lLLVMRuntimeDyld \
-lLLVMCodeGen \
-lLLVMTarget \
-lLLVMScalarOpts \
-lLLVMInstCombine \
-lLLVMInstrumentation \
-lLLVMProfileData \
-lLLVMObject \
-lLLVMMCParser \
-lLLVMTransformUtils \
-lLLVMMC \
-lLLVMBitWriter \
-lLLVMBitReader \
-lLLVMAnalysis \
-lLLVMCore \
-lLLVMSupport \
-lz \
-lpthread \
-ledit \
-lcurses \
-lm \
 \
-L/usr/local/Cellar/gmp/6.0.0a/lib \
-L/opt/local/lib \
-L/usr/lib \
-Wl,-object_path_lto,clasp.lto.o \
-Wl,-stack_size,0x1000000 \
-fvisibility=default \
-lc++ \
-lto_library \
/Users/meister/Development/externals-clasp/build/release/lib/libLTO.dylib \
-rdynamic \
-stdlib=libc++ \
-L"/Users/meister/Development/clasp/build/clasp/Contents/Resources/lib/common/lib" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangAnalysis.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangARCMigrate.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangAST.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangASTMatchers.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangBasic.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangCodeGen.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangDriver.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangDynamicASTMatchers.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangEdit.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangFormat.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangFrontend.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangFrontendTool.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangIndex.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangLex.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangParse.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangRewrite.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangRewriteFrontend.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangSema.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangSerialization.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangStaticAnalyzerCheckers.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangStaticAnalyzerCore.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangStaticAnalyzerFrontend.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangTooling.a" \
"/Users/meister/Development/externals-clasp/build/release/lib/libclangToolingCore.a" \
 \
 \
 \
 \
 \
-lboost_filesystem \
-lboost_regex \
-lboost_date_time \
-lboost_program_options \
-lboost_system \
-lboost_iostreams \
-lgmp \
-lgmpxx \
-lexpat \
-lz \
-lncurses \
-lreadline \
-lgc 

