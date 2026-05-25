#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

BOOL MouseLensAppendSampleBufferCatchingException(
    AVAssetWriterInput *input,
    CMSampleBufferRef sampleBuffer,
    CFStringRef *errorMessageOut
) {
    @try {
        return [input appendSampleBuffer:sampleBuffer];
    } @catch (NSException *exception) {
        if (errorMessageOut != NULL) {
            NSString *reason = exception.reason ?: @"No reason provided";
            NSString *message = [NSString stringWithFormat:@"%@: %@", exception.name, reason];
            *errorMessageOut = CFBridgingRetain(message);
        }
        return NO;
    }
}
