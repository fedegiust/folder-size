#import <Cocoa/Cocoa.h>

/// The app's single window: a drive picker, the folder tree on the left and the treemap on the right.
@interface MainWindowController : NSWindowController

- (IBAction)scanSelectedLocation:(id)sender;
- (IBAction)chooseFolder:(id)sender;
- (IBAction)stopScan:(id)sender;
- (IBAction)goUp:(id)sender;
- (IBAction)revealNode:(id)sender;
- (IBAction)trashNode:(id)sender;

@end
