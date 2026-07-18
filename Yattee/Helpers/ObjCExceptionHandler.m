//
//  ObjCExceptionHandler.m
//  Yattee
//
//  Catches ObjC NSExceptions that Swift cannot handle natively.
//

#import "ObjCExceptionHandler.h"

BOOL tryCatchObjCException(void (NS_NOESCAPE ^block)(void), NSException *_Nullable *_Nullable outException) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outException) {
            *outException = exception;
        }
        return NO;
    }
}
