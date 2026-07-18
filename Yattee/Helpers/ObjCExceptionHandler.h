//
//  ObjCExceptionHandler.h
//  Yattee
//
//  Catches ObjC NSExceptions that Swift cannot handle natively.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes a block and catches any NSException thrown.
/// Returns YES if the block executed without throwing, NO if an exception was caught.
/// If an exception is caught, it is returned via the outException parameter.
BOOL tryCatchObjCException(void (NS_NOESCAPE ^block)(void), NSException *_Nullable *_Nullable outException);

NS_ASSUME_NONNULL_END
