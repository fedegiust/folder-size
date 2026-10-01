#import <Cocoa/Cocoa.h>

/// A small bar plus percentage, used in the tree's "% of Parent" column.
@interface PercentBarView : NSView
@property (nonatomic) double fraction;  // 0...1
@end
