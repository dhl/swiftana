#include "llvm/ADT/SmallVector.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Transforms/Utils/ModuleUtils.h"

using namespace llvm;

namespace {
class SwiftLiteralNormalizePass
    : public PassInfoMixin<SwiftLiteralNormalizePass> {
public:
  PreservedAnalyses run(Module &M, ModuleAnalysisManager &) {
    SmallVector<GlobalValue *, 8> LiteralGlobals;
    bool Changed = false;

    for (GlobalVariable &GV : M.globals()) {
      if (!GV.hasInitializer() || !GV.isConstant() || !GV.getSection().empty())
        continue;

      auto *CDA = dyn_cast<ConstantDataArray>(GV.getInitializer());
      if (!CDA || !CDA->isCString())
        continue;

      auto *ArrayTy = dyn_cast<ArrayType>(GV.getValueType());
      if (!ArrayTy || !ArrayTy->getElementType()->isIntegerTy(8))
        continue;

      StringRef Name = GV.getName();
      if (!Name.consume_front(".str."))
        continue;

      if (GV.hasPrivateLinkage()) {
        GV.setLinkage(GlobalValue::InternalLinkage);
        Changed = true;
      }

      if (GV.getUnnamedAddr() != GlobalValue::UnnamedAddr::None) {
        GV.setUnnamedAddr(GlobalValue::UnnamedAddr::None);
        Changed = true;
      }

      LiteralGlobals.push_back(&GV);
    }

    if (!LiteralGlobals.empty())
      appendToCompilerUsed(M, LiteralGlobals);

    return Changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
  }
};

class SwiftCallingConventionNormalizePass
    : public PassInfoMixin<SwiftCallingConventionNormalizePass> {
public:
  PreservedAnalyses run(Module &M, ModuleAnalysisManager &) {
    bool Changed = false;

    auto UpdateCallConvUses = [&](Function &F) {
      SmallVector<User *, 8> WorkList(F.users().begin(), F.users().end());
      while (!WorkList.empty()) {
        User *U = WorkList.pop_back_val();
        if (auto *CE = dyn_cast<ConstantExpr>(U)) {
          WorkList.append(CE->users().begin(), CE->users().end());
          continue;
        }

        if (auto *CB = dyn_cast<CallBase>(U))
          if (CB->getCallingConv() == CallingConv::Swift) {
            CB->setCallingConv(CallingConv::C);
            Changed = true;
          }
      }
    };

    for (Function &F : M) {
      if (F.isDeclaration())
        continue;

      if (F.getCallingConv() == CallingConv::Swift) {
        F.setCallingConv(CallingConv::C);
        Changed = true;
      }

      UpdateCallConvUses(F);
    }

    return Changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
  }
};
} // namespace

PassPluginLibraryInfo getSwiftBPFPreparePassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "SwiftBPFPreparePass", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, ModulePassManager &MPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "swift-literal-normalize") {
                    MPM.addPass(SwiftLiteralNormalizePass());
                    return true;
                  }
                  if (Name == "swift-cc-normalize") {
                    MPM.addPass(SwiftCallingConventionNormalizePass());
                    return true;
                  }
                  return false;
                });
          }};
}

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return getSwiftBPFPreparePassPluginInfo();
}
