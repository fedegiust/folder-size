#import <Foundation/Foundation.h>

/// One file or folder in a scanned tree. A folder's size includes everything inside it.
@interface FileNode : NSObject

@property (nonatomic, copy) NSString *name;
/// Not retained: parents own their children, and weak references are too slow for
/// trees with millions of nodes. Cleared when a node is removed from the tree.
@property (nonatomic, unsafe_unretained) FileNode *parent;
/// nil for files, sorted largest first for folders.
@property (nonatomic, strong) NSMutableArray<FileNode *> *children;
/// Bytes allocated on disk, which is the space you get back by deleting it.
@property (nonatomic) unsigned long long size;
/// Number of files inside a folder, or 1 for a file.
@property (nonatomic) unsigned long long fileCount;
@property (nonatomic) BOOL isHidden;
/// macOS refused to list this folder's contents, so its size is incomplete.
@property (nonatomic) BOOL isUnreadable;

+ (instancetype)fileNamed:(NSString *)name size:(unsigned long long)size;
/// The root folder of a scan is named with its full path.
+ (instancetype)folderNamed:(NSString *)name;

@property (nonatomic, readonly) BOOL isFolder;
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSURL *fileURL;

- (void)addChild:(FileNode *)child;
- (void)sortChildrenBySize;
- (BOOL)isDescendantOf:(FileNode *)ancestor;  // YES for the node itself

/// These keep the sizes and sort order of every folder above them up to date.
- (void)removeChild:(FileNode *)child;
- (void)replaceChild:(FileNode *)oldChild withNode:(FileNode *)newChild;

@end

NSString *FormatBytes(unsigned long long bytes);
NSString *FormatCount(unsigned long long count);
