#import <Foundation/Foundation.h>

@class FileNode;

typedef void (^ScanProgressHandler)(unsigned long long fileCount, unsigned long long byteCount, NSString *currentFolder);
/// root is nil when the scan was cancelled or the path could not be opened.
typedef void (^ScanCompletionHandler)(FileNode *root);

/// Walks a folder tree on a background thread, hidden items included, and builds a
/// FileNode tree of sizes on disk. Both handlers are called on the main thread.
@interface Scanner : NSObject

- (instancetype)initWithRootPath:(NSString *)rootPath;

@property (nonatomic, readonly) NSString *rootPath;
@property (atomic, readonly, getter=isCancelled) BOOL cancelled;
/// Folders macOS would not let us list, usually privacy-protected ones (see Full Disk Access).
@property (nonatomic, readonly) NSUInteger unreadableFolderCount;
@property (nonatomic, readonly) NSTimeInterval duration;

- (void)startWithProgress:(ScanProgressHandler)progress completion:(ScanCompletionHandler)completion;
- (void)cancel;

@end
