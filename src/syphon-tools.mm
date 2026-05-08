/*
 * obs-syphon-server — single "Syphon" Tools menu entry that opens a
 * native Cocoa settings panel.
 *
 *   Tools → Syphon…
 *
 * Panel content:
 *   ☐ Publish Program output  (server name: OBS)
 *   ☐ Publish Preview output  (server name: OBS Preview)
 *   [Close]
 *
 * The window is a singleton NSPanel so re-opening focuses it instead of
 * spawning duplicates.
 */

#include "syphon-tools.h"
#include "syphon-publisher.h"
#include "plugin-support.h"

#include <obs-module.h>
#include <obs-frontend-api.h>

#import <Cocoa/Cocoa.h>

/* ── Window controller ──────────────────────────────────────────────── */

@interface SyphonSettingsWindow : NSWindowController <NSWindowDelegate>
@property(nonatomic, strong) NSButton *programCheckbox;
@property(nonatomic, strong) NSButton *previewCheckbox;
@end

@implementation SyphonSettingsWindow

+ (instancetype)shared
{
    static SyphonSettingsWindow *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[SyphonSettingsWindow alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    NSRect frame = NSMakeRect(0, 0, 380, 200);
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [panel setTitle:@"Syphon Server"];
    [panel setReleasedWhenClosed:NO];
    [panel setFloatingPanel:NO];
    [panel setHidesOnDeactivate:NO];
    [panel center];

    self = [super initWithWindow:panel];
    if (!self)
        return nil;

    panel.delegate = self;

    NSView *content = panel.contentView;

    /* Header label */
    NSTextField *header = [NSTextField labelWithString:@"Syphon outputs"];
    header.font = [NSFont boldSystemFontOfSize:13];
    header.frame = NSMakeRect(20, 160, 340, 20);
    [content addSubview:header];

    /* Program checkbox */
    NSString *progLabel =
        [NSString stringWithFormat:@"Publish Program output  (server name: \"%s\")", syphon_publisher_name(SY_OUT_PROGRAM)];
    self.programCheckbox = [NSButton checkboxWithTitle:progLabel
                                                target:self
                                                action:@selector(onProgramToggled:)];
    self.programCheckbox.frame = NSMakeRect(20, 125, 340, 20);
    [content addSubview:self.programCheckbox];

    /* Preview checkbox */
    NSString *prevLabel =
        [NSString stringWithFormat:@"Publish Preview output  (server name: \"%s\")", syphon_publisher_name(SY_OUT_PREVIEW)];
    self.previewCheckbox = [NSButton checkboxWithTitle:prevLabel
                                                target:self
                                                action:@selector(onPreviewToggled:)];
    self.previewCheckbox.frame = NSMakeRect(20, 95, 340, 20);
    [content addSubview:self.previewCheckbox];

    /* Hint */
    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"Tip: apply the “Syphon Server” video filter to any source or scene "
        @"to publish that source as its own Syphon server."];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.frame = NSMakeRect(20, 45, 340, 40);
    [content addSubview:hint];

    /* Close button */
    NSButton *close = [NSButton buttonWithTitle:@"Close"
                                         target:self
                                         action:@selector(onClose:)];
    close.bezelStyle = NSBezelStyleRounded;
    close.keyEquivalent = @"\r";
    close.frame = NSMakeRect(285, 12, 80, 28);
    [content addSubview:close];

    [self syncFromState];
    return self;
}

- (void)syncFromState
{
    self.programCheckbox.state =
        syphon_publisher_is_enabled(SY_OUT_PROGRAM) ? NSControlStateValueOn : NSControlStateValueOff;
    self.previewCheckbox.state =
        syphon_publisher_is_enabled(SY_OUT_PREVIEW) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)onProgramToggled:(NSButton *)sender
{
    syphon_publisher_set_enabled(SY_OUT_PROGRAM, sender.state == NSControlStateValueOn);
}

- (void)onPreviewToggled:(NSButton *)sender
{
    syphon_publisher_set_enabled(SY_OUT_PREVIEW, sender.state == NSControlStateValueOn);
}

- (void)onClose:(id)sender
{
    (void) sender;
    [self.window orderOut:nil];
}

- (void)show
{
    [self syncFromState];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end

/* ── Tools menu hook ────────────────────────────────────────────────── */

static void open_settings_cb(void *unused)
{
    (void) unused;
    @autoreleasepool {
        [[SyphonSettingsWindow shared] show];
    }
}

extern "C" void syphon_tools_register(void)
{
    obs_frontend_add_tools_menu_item("Syphon…", open_settings_cb, nullptr);
    obs_log(LOG_INFO, "Tools menu: Syphon… registered");
}
