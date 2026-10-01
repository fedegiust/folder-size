#import "Scanner.h"
#import "FileNode.h"
#include <fts.h>
#include <sys/stat.h>

static NSString *const kDataVolumePath = @"/System/Volumes/Data";

static NSString *StringFromFileSystemPath(const char *path, size_t length) {
    NSString *string = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:length];
    // Names that are not valid UTF-8 (rare, mostly on old external drives) must still show up.
    return string ?: [[NSString alloc] initWithBytes:path length:length encoding:NSISOLatin1StringEncoding];
}

static NSString *NameOfEntry(FTSENT *entry) {
    return StringFromFileSystemPath(entry->fts_name, entry->fts_namelen);
}

static BOOL IsHiddenEntry(FTSENT *entry) {
    return entry->fts_name[0] == '.' || (entry->fts_statp->st_flags & UF_HIDDEN) != 0;
}

static unsigned long long AllocatedSize(const struct stat *info) {
    return (unsigned long long)info->st_blocks * 512;
}

@interface Scanner ()
@property (atomic, readwrite, getter=isCancelled) BOOL cancelled;
@end

@implementation Scanner {
    NSSet<NSNumber *> *_devicesToScan;
    NSString *_pathToSkip;
}

- (instancetype)initWithRootPath:(NSString *)rootPath {
    if ((self = [super init])) {
        _rootPath = [rootPath copy];
    }
    return self;
}

- (void)cancel {
    self.cancelled = YES;
}

- (void)startWithProgress:(ScanProgressHandler)progress completion:(ScanCompletionHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        FileNode *root = [self scanReportingProgress:progress];
        self->_duration = CFAbsoluteTimeGetCurrent() - start;
        if (self.isCancelled) root = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(root);
        });
    });
}

#pragma mark - Walking the tree

- (FileNode *)scanReportingProgress:(ScanProgressHandler)progress {
    [self prepareVolumeRules];

    char *paths[] = { (char *)_rootPath.fileSystemRepresentation, NULL };
    // FTS_NOCHDIR: we run on a background thread, and changing the working directory is process-wide.
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_COMFOLLOW | FTS_NOCHDIR, NULL);
    if (!fts) return nil;

    NSMutableArray<FileNode *> *openFolders = [NSMutableArray array];  // from the root down to the current folder
    NSMutableSet<NSString *> *seenHardLinks = [NSMutableSet set];
    FileNode *root = nil;
    unsigned long long fileCount = 0, byteCount = 0, visitCount = 0;
    CFAbsoluteTime lastReport = 0;
    FTSENT *entry;

    while (!self.isCancelled && (entry = fts_read(fts)) != NULL) {
        @autoreleasepool {
            FileNode *parent = openFolders.lastObject;

            switch (entry->fts_info) {
                case FTS_D: {
                    if (entry->fts_level > 0 && [self shouldSkipFolder:entry]) {
                        // fts still reports the folder once more as FTS_DP; fts_number stays 0 so we ignore it.
                        fts_set(fts, entry, FTS_SKIP);
                        break;
                    }
                    FileNode *folder = [FileNode folderNamed:(entry->fts_level == 0 ? _rootPath : NameOfEntry(entry))];
                    folder.size = AllocatedSize(entry->fts_statp);
                    folder.isHidden = IsHiddenEntry(entry);
                    [parent addChild:folder];
                    [openFolders addObject:folder];
                    entry->fts_number = 1;
                    root = root ?: folder;
                    byteCount += folder.size;
                    break;
                }
                case FTS_DP:
                    if (entry->fts_number == 1) [self closeFolderIn:openFolders];
                    break;

                case FTS_DNR:
                case FTS_ERR:
                    // A folder we opened but may not list comes back with one of these instead of FTS_DP.
                    if (entry->fts_number == 1) {
                        openFolders.lastObject.isUnreadable = YES;
                        _unreadableFolderCount++;
                        [self closeFolderIn:openFolders];
                    } else if (entry->fts_info == FTS_DNR) {
                        FileNode *folder = [FileNode folderNamed:NameOfEntry(entry)];
                        folder.isUnreadable = YES;
                        [parent addChild:folder];
                        _unreadableFolderCount++;
                    }
                    break;

                case FTS_F:
                case FTS_SL:
                case FTS_SLNONE:
                case FTS_DEFAULT: {
                    FileNode *file = [FileNode fileNamed:NameOfEntry(entry)
                                                    size:[self sizeOfFile:entry seenHardLinks:seenHardLinks]];
                    file.isHidden = IsHiddenEntry(entry);
                    [parent addChild:file];
                    parent.size += file.size;
                    parent.fileCount += 1;
                    fileCount++;
                    byteCount += file.size;
                    break;
                }
                default:  // FTS_NS (could not stat) and FTS_DC (directory cycle) add nothing
                    break;
            }

            if (progress && ++visitCount % 512 == 0) {
                CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                if (now - lastReport > 0.1) {
                    lastReport = now;
                    NSString *current = StringFromFileSystemPath(entry->fts_path, entry->fts_pathlen);
                    unsigned long long files = fileCount, bytes = byteCount;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progress(files, bytes, current);
                    });
                }
            }
        }
    }

    fts_close(fts);
    return self.isCancelled ? nil : root;
}

/// Called once everything inside the innermost open folder has been seen.
- (void)closeFolderIn:(NSMutableArray<FileNode *> *)openFolders {
    FileNode *folder = openFolders.lastObject;
    [openFolders removeLastObject];
    [folder sortChildrenBySize];
    FileNode *parent = openFolders.lastObject;
    parent.size += folder.size;
    parent.fileCount += folder.fileCount;
}

/// A file with several hard links takes its space once, so only the first link counts.
- (unsigned long long)sizeOfFile:(FTSENT *)entry seenHardLinks:(NSMutableSet<NSString *> *)seenHardLinks {
    const struct stat *info = entry->fts_statp;
    if (entry->fts_info == FTS_F && info->st_nlink > 1) {
        NSString *key = [NSString stringWithFormat:@"%d:%llu", info->st_dev, (unsigned long long)info->st_ino];
        if ([seenHardLinks containsObject:key]) return 0;
        [seenHardLinks addObject:key];
    }
    return AllocatedSize(info);
}

#pragma mark - Staying on the right volume

/// Other drives are mounted inside the tree (/Volumes, network shares, /dev), so we only
/// enter folders on the volume being scanned; otherwise they would be counted twice.
- (void)prepareVolumeRules {
    NSMutableSet<NSNumber *> *devices = [NSMutableSet set];
    struct stat info;
    if (stat(_rootPath.fileSystemRepresentation, &info) == 0) {
        [devices addObject:@(info.st_dev)];
    }
    // Since macOS 10.15 the startup disk is a read-only system volume at "/" plus a data volume
    // at /System/Volumes/Data whose folders also appear in "/" (/Users, /Applications, ...).
    // A scan of "/" has to cross into the data volume, but only through "/", not a second time.
    if ([_rootPath isEqualToString:@"/"] && stat(kDataVolumePath.fileSystemRepresentation, &info) == 0) {
        [devices addObject:@(info.st_dev)];
        _pathToSkip = kDataVolumePath;
    }
    _devicesToScan = devices;
}

- (BOOL)shouldSkipFolder:(FTSENT *)entry {
    if (![_devicesToScan containsObject:@(entry->fts_statp->st_dev)]) return YES;
    return _pathToSkip && strcmp(entry->fts_path, _pathToSkip.fileSystemRepresentation) == 0;
}

@end
