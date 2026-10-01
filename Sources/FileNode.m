#import "FileNode.h"

@implementation FileNode

+ (instancetype)fileNamed:(NSString *)name size:(unsigned long long)size {
    FileNode *node = [[self alloc] init];
    node.name = name;
    node.size = size;
    node.fileCount = 1;
    return node;
}

+ (instancetype)folderNamed:(NSString *)name {
    FileNode *node = [[self alloc] init];
    node.name = name;
    node.children = [NSMutableArray array];
    return node;
}

- (BOOL)isFolder {
    return self.children != nil;
}

- (NSString *)path {
    return self.parent ? [self.parent.path stringByAppendingPathComponent:self.name] : self.name;
}

- (NSURL *)fileURL {
    return [NSURL fileURLWithPath:self.path isDirectory:self.isFolder];
}

- (void)addChild:(FileNode *)child {
    child.parent = self;
    [self.children addObject:child];
}

- (void)sortChildrenBySize {
    [self.children sortUsingComparator:^NSComparisonResult(FileNode *a, FileNode *b) {
        if (a.size != b.size) {
            return a.size > b.size ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.name caseInsensitiveCompare:b.name];
    }];
}

- (BOOL)isDescendantOf:(FileNode *)ancestor {
    for (FileNode *node = self; node; node = node.parent) {
        if (node == ancestor) return YES;
    }
    return NO;
}

- (void)removeChild:(FileNode *)child {
    NSUInteger index = [self.children indexOfObjectIdenticalTo:child];
    if (index == NSNotFound) return;
    [self.children removeObjectAtIndex:index];
    child.parent = nil;
    [self adjustSizeBy:-(long long)child.size fileCountBy:-(long long)child.fileCount];
}

- (void)replaceChild:(FileNode *)oldChild withNode:(FileNode *)newChild {
    NSUInteger index = [self.children indexOfObjectIdenticalTo:oldChild];
    if (index == NSNotFound) return;
    self.children[index] = newChild;
    newChild.parent = self;
    oldChild.parent = nil;
    [self adjustSizeBy:(long long)newChild.size - (long long)oldChild.size
           fileCountBy:(long long)newChild.fileCount - (long long)oldChild.fileCount];
}

- (void)adjustSizeBy:(long long)sizeDelta fileCountBy:(long long)countDelta {
    for (FileNode *node = self; node; node = node.parent) {
        node.size = (unsigned long long)((long long)node.size + sizeDelta);
        node.fileCount = (unsigned long long)((long long)node.fileCount + countDelta);
        [node sortChildrenBySize];
    }
}

@end

NSString *FormatBytes(unsigned long long bytes) {
    static NSByteCountFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
    });
    return [formatter stringFromByteCount:(long long)bytes];
}

NSString *FormatCount(unsigned long long count) {
    static NSNumberFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
    });
    return [formatter stringFromNumber:@(count)];
}
