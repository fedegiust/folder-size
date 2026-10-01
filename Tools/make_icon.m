// Draws the app icon (a rounded tile holding a small treemap) into an .iconset folder.
// Usage: make_icon <output.iconset>
#import <Cocoa/Cocoa.h>

typedef struct {
    CGFloat x, y, width, height, hue;
} Block;

static void DrawIcon(CGFloat pixels) {
    CGFloat scale = pixels / 1024.0;
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:scale];
    [transform concat];

    // Tile proportions follow Apple's icon grid: 824 points inside a 1024 canvas.
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(100, 100, 824, 824) xRadius:185 yRadius:185];
    NSGradient *background = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.99 alpha:1]
                                                           endingColor:[NSColor colorWithCalibratedWhite:0.84 alpha:1]];
    [background drawInBezierPath:tile angle:-90];

    Block blocks[] = {
        { 180, 180, 380, 664, 0.58 },
        { 580, 520, 264, 324, 0.08 },
        { 580, 340, 264, 160, 0.36 },
        { 580, 180, 150, 140, 0.75 },
        { 750, 180,  94, 140, 0.14 },
    };
    for (size_t i = 0; i < sizeof(blocks) / sizeof(blocks[0]); i++) {
        Block block = blocks[i];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(block.x, block.y, block.width, block.height)
                                                             xRadius:28 yRadius:28];
        NSGradient *fill = [[NSGradient alloc]
            initWithStartingColor:[NSColor colorWithCalibratedHue:block.hue saturation:0.45 brightness:1.0 alpha:1]
                      endingColor:[NSColor colorWithCalibratedHue:block.hue saturation:0.70 brightness:0.80 alpha:1]];
        [fill drawInBezierPath:path angle:-45];
    }
}

static BOOL WritePNG(NSString *path, NSInteger pixels) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:pixels
                                                                       pixelsHigh:pixels
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSCalibratedRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
    DrawIcon(pixels);
    [NSGraphicsContext restoreGraphicsState];
    return [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: make_icon <output.iconset>\n");
            return 1;
        }
        NSString *folder = @(argv[1]);
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSNumber *points in @[ @16, @32, @128, @256, @512 ]) {
            NSInteger size = points.integerValue;
            NSString *normal = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%ldx%ld.png", size, size]];
            NSString *retina = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%ldx%ld@2x.png", size, size]];
            if (!WritePNG(normal, size) || !WritePNG(retina, size * 2)) return 1;
        }
    }
    return 0;
}
