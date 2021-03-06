/* $Id: Controller.mm,v 1.79 2005/11/04 19:41:32 titer Exp $

   This file is part of the HandBrake source code.
   Homepage: <http://handbrake.m0k.org/>.
   It may be used under the terms of the GNU General Public License. */

#include "Controller.h"
#include "a52dec/a52.h"
#import "HBOutputPanelController.h"
#import "HBPreferencesController.h"

#define _(a) NSLocalizedString(a,NULL)

static int FormatSettings[4][10] =
  { { HB_MUX_MP4 | HB_VCODEC_FFMPEG | HB_ACODEC_FAAC,
	  HB_MUX_MP4 | HB_VCODEC_X264   | HB_ACODEC_FAAC,
	  0,
	  0},
    { HB_MUX_AVI | HB_VCODEC_FFMPEG | HB_ACODEC_LAME,
	  HB_MUX_AVI | HB_VCODEC_FFMPEG | HB_ACODEC_AC3,
	  HB_MUX_AVI | HB_VCODEC_X264   | HB_ACODEC_LAME,
	  HB_MUX_AVI | HB_VCODEC_X264   | HB_ACODEC_AC3},
    { HB_MUX_OGM | HB_VCODEC_FFMPEG | HB_ACODEC_VORBIS,
	  HB_MUX_OGM | HB_VCODEC_FFMPEG | HB_ACODEC_LAME,
	  0,
	  0 },
    { HB_MUX_MKV | HB_VCODEC_FFMPEG | HB_ACODEC_FAAC,
	  HB_MUX_MKV | HB_VCODEC_FFMPEG | HB_ACODEC_AC3,
	  HB_MUX_MKV | HB_VCODEC_FFMPEG | HB_ACODEC_LAME,
	  HB_MUX_MKV | HB_VCODEC_FFMPEG | HB_ACODEC_VORBIS,
	  HB_MUX_MKV | HB_VCODEC_X264   | HB_ACODEC_FAAC,
	  HB_MUX_MKV | HB_VCODEC_X264   | HB_ACODEC_AC3,
	  HB_MUX_MKV | HB_VCODEC_X264   | HB_ACODEC_LAME,
	  HB_MUX_MKV | HB_VCODEC_X264   | HB_ACODEC_VORBIS,
	  0,
	  0 } };

/* We setup the toolbar values here */
static NSString*       MyDocToolbarIdentifier          = @"My Document Toolbar Identifier";
static NSString*       ToggleDrawerIdentifier  = @"Toggle Drawer Item Identifier";
//static NSString*       ToggleDrawerIdentifier  = @"Toggle Presets Item Identifier";
static NSString*       StartEncodingIdentifier         = @"Start Encoding Item Identifier";
static NSString*       PauseEncodingIdentifier         = @"Pause Encoding Item Identifier";
static NSString*       ShowQueueIdentifier     = @"Show Queue Item Identifier";
static NSString*       AddToQueueIdentifier    = @"Add to Queue Item Identifier";
static NSString*       DebugOutputIdentifier   = @"Debug Output Item Identifier";
static NSString*       ChooseSourceIdentifier   = @"Choose Source Item Identifier";

/*******************************
 * HBController implementation *
 *******************************/
@implementation HBController

- init
{
    self = [super init];
    [HBPreferencesController registerUserDefaults];
    fHandle = NULL;
    outputPanel = [[HBOutputPanelController alloc] init];
    return self;
}

- (void) applicationDidFinishLaunching: (NSNotification *) notification
{
    int    build;
    char * version;

    // Open debug output window now if it was visible when HB was closed
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OutputPanelIsOpen"])
        [self showDebugOutputPanel:nil];

    // Init libhb
	int debugLevel = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowVerboseOutput"] ? HB_DEBUG_ALL : HB_DEBUG_NONE;
    fHandle = hb_init(debugLevel, [[NSUserDefaults standardUserDefaults] boolForKey:@"CheckForUpdates"]);

	// Set the Growl Delegate
	HBController *hbGrowlDelegate = [[HBController alloc] init];
	[GrowlApplicationBridge setGrowlDelegate: hbGrowlDelegate];    
    /* Init others controllers */
    [fScanController    SetHandle: fHandle];
    [fPictureController SetHandle: fHandle];
    [fQueueController   SetHandle: fHandle];
	
    fChapterTitlesDelegate = [[ChapterTitles alloc] init];
    [fChapterTable setDataSource:fChapterTitlesDelegate];

     /* Call UpdateUI every 2/10 sec */
    [[NSRunLoop currentRunLoop] addTimer: [NSTimer
        scheduledTimerWithTimeInterval: 0.2 target: self
        selector: @selector( UpdateUI: ) userInfo: NULL repeats: FALSE]
        forMode: NSModalPanelRunLoopMode];

    if( ( build = hb_check_update( fHandle, &version ) ) > -1 )
    {
        /* Update available - tell the user */
	
        NSBeginInformationalAlertSheet( _( @"Update is available" ),
            _( @"Go get it!" ), _( @"Discard" ), NULL, fWindow, self,
            @selector( UpdateAlertDone:returnCode:contextInfo: ),
            NULL, NULL, [NSString stringWithFormat:
            _( @"HandBrake %s (build %d) is now available for download." ),
            version, build] );
        return;

    }

    /* Show scan panel ASAP */
    [self performSelectorOnMainThread: @selector(ShowScanPanel:)
        withObject: NULL waitUntilDone: NO];
}

- (NSApplicationTerminateReply) applicationShouldTerminate:
    (NSApplication *) app
{
    if( [[fRipButton title] isEqualToString: _( @"Cancel" )] )
    {
        [self Cancel: NULL];
        return NSTerminateCancel;
    }    
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	[outputPanel release];
	hb_close(&fHandle);
}


- (void) awakeFromNib
{
    [fWindow center];

    [self TranslateStrings];
    currentScanCount = 0;

//[self registrationDictionaryForGrowl];
/* Init User Presets .plist */
	/* We declare the default NSFileManager into fileManager */
	NSFileManager * fileManager = [NSFileManager defaultManager];
	//presetPrefs = [[NSUserDefaults standardUserDefaults] retain];
	/* we set the files and support paths here */
	AppSupportDirectory = @"~/Library/Application Support/HandBrake";
    AppSupportDirectory = [AppSupportDirectory stringByExpandingTildeInPath];
    
	UserPresetsFile = @"~/Library/Application Support/HandBrake/UserPresets.plist";
    UserPresetsFile = [UserPresetsFile stringByExpandingTildeInPath];
	
	x264ProfilesFile = @"~/Library/Application Support/HandBrake/x264Profiles.plist";
    x264ProfilesFile = [x264ProfilesFile stringByExpandingTildeInPath];
	/* We check for the app support directory for media fork */
	if ([fileManager fileExistsAtPath:AppSupportDirectory] == 0) 
	{
		// If it doesnt exist yet, we create it here 
		[fileManager createDirectoryAtPath:AppSupportDirectory attributes:nil];
	}
	// We check for the presets.plist here
	
	if ([fileManager fileExistsAtPath:UserPresetsFile] == 0) 
	{

		[fileManager createFileAtPath:UserPresetsFile contents:nil attributes:nil];
		
	}
	// We check for the x264profiles.plist here
	 
	if ([fileManager fileExistsAtPath:x264ProfilesFile] == 0) 
	{
        
		[fileManager createFileAtPath:x264ProfilesFile contents:nil attributes:nil];
	}
    
	
  UserPresetsFile = @"~/Library/Application Support/HandBrake/UserPresets.plist";
  UserPresetsFile = [[UserPresetsFile stringByExpandingTildeInPath]retain];

  UserPresets = [[NSMutableArray alloc] initWithContentsOfFile:UserPresetsFile];
  if (nil == UserPresets) 
  {
    UserPresets = [[NSMutableArray alloc] init];
	[self AddFactoryPresets:NULL];
  }
  /* Show/Dont Show Presets drawer upon launch based
  on user preference DefaultPresetsDrawerShow*/
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultPresetsDrawerShow"] > 0)
		{
	  [fPresetDrawer open];
		}



    /* Destination box*/
    [fDstFormatPopUp removeAllItems];
    [fDstFormatPopUp addItemWithTitle: _( @"MP4 file" )];
    [fDstFormatPopUp addItemWithTitle: _( @"AVI file" )];
    [fDstFormatPopUp addItemWithTitle: _( @"OGM file" )];
	[fDstFormatPopUp addItemWithTitle: _( @"MKV file" )];
    [fDstFormatPopUp selectItemAtIndex: 0];

    [self FormatPopUpChanged: NULL];
    
	/* We enable the create chapters checkbox here since we are .mp4 */	
	[fCreateChapterMarkers setEnabled: YES];
	if ([fDstFormatPopUp indexOfSelectedItem] == 0 && [[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultChapterMarkers"] > 0)
	{
		[fCreateChapterMarkers setState: NSOnState];
	}
	

	
	
    [fDstFile2Field setStringValue: [NSString stringWithFormat:
        @"%@/Desktop/Movie.mp4", NSHomeDirectory()]];

    /* Video encoder */
    [fVidEncoderPopUp removeAllItems];
    [fVidEncoderPopUp addItemWithTitle: @"FFmpeg"];
    [fVidEncoderPopUp addItemWithTitle: @"XviD"];

    
	
    /* Video quality */
    [fVidTargetSizeField setIntValue: 700];
	[fVidBitrateField    setIntValue: 1000];

    [fVidQualityMatrix   selectCell: fVidBitrateCell];
    [self VideoMatrixChanged: NULL];

    /* Video framerate */
    [fVidRatePopUp removeAllItems];
	[fVidRatePopUp addItemWithTitle: _( @"Same as source" )];
    for( int i = 0; i < hb_video_rates_count; i++ )
    {
        [fVidRatePopUp addItemWithTitle:
            [NSString stringWithCString: hb_video_rates[i].string]];
    }
    [fVidRatePopUp selectItemAtIndex: 0];
	
	/* Picture Settings */
	[fPicLabelPAROutp setStringValue: @""];
	[fPicLabelPAROutputX setStringValue: @""];
	[fPicSettingPARWidth setStringValue: @""];
	[fPicSettingPARHeight setStringValue:  @""];
	
    /* Audio bitrate */
    [fAudBitratePopUp removeAllItems];
    for( int i = 0; i < hb_audio_bitrates_count; i++ )
    {
        [fAudBitratePopUp addItemWithTitle:
            [NSString stringWithCString: hb_audio_bitrates[i].string]];
    }
    [fAudBitratePopUp selectItemAtIndex: hb_audio_bitrates_default];

    /* Audio samplerate */
    [fAudRatePopUp removeAllItems];
    for( int i = 0; i < hb_audio_rates_count; i++ )
    {
        [fAudRatePopUp addItemWithTitle:
            [NSString stringWithCString: hb_audio_rates[i].string]];
    }
    [fAudRatePopUp selectItemAtIndex: hb_audio_rates_default];

    /* Bottom */
    [fStatusField setStringValue: @""];

    [self EnableUI: NO];
    //[fPauseButton setEnabled: NO];
    //[fRipButton setEnabled: NO];
	/* Use new Toolbar start and pause here */
	
	pauseButtonEnabled = NO;
	startButtonEnabled = NO;
       [self setupToolbar];
	/* In Ritsuka's patch, this goes below the Turbo stuff below
	   Lets try to keep it all together */
       startButtonEnabled = NO;
       stopOrStart = NO;
       AddToQueueButtonEnabled = NO;
       pauseButtonEnabled = NO;
       resumeOrPause = NO;

	/* We disable the Turbo 1st pass checkbox since we are not x264 */
	[fVidTurboPassCheck setEnabled: NO];
	[fVidTurboPassCheck setState: NSOffState];
}

// ============================================================
// NSToolbar Related Methods
// ============================================================

- (void) setupToolbar {
    // Create a new toolbar instance, and attach it to our document window 
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier: MyDocToolbarIdentifier] autorelease];
    
    // Set up toolbar properties: Allow customization, give a default display mode, and remember state in user defaults 
    [toolbar setAllowsUserCustomization: YES];
    [toolbar setAutosavesConfiguration: YES];
    [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
    
    // We are the delegate
    [toolbar setDelegate: self];
    
    // Attach the toolbar to the document window 
    [fWindow setToolbar: toolbar];
}

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier: (NSString *) itemIdent willBeInsertedIntoToolbar:(BOOL) willBeInserted {
    // Required delegate method:  Given an item identifier, this method returns an item 
    // The toolbar will use this method to obtain toolbar items that can be displayed in the customization sheet, or in the toolbar itself 
    NSToolbarItem *toolbarItem = nil;
    
    if ([itemIdent isEqual: ToggleDrawerIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
		
        // Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: @"Toggle Presets"];
		[toolbarItem setPaletteLabel: @"Toggler Presets"];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: @"Open/Close Preset Drawer"];
		[toolbarItem setImage: [NSImage imageNamed: @"Drawer-List2"]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(toggleDrawer)];
		
	} else if ([itemIdent isEqual: StartEncodingIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
		
        // Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: @"Start"];
		[toolbarItem setPaletteLabel: @"Start Encoding"];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: @"Start Encoding"];
		[toolbarItem setImage: [NSImage imageNamed: @"Play"]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(Rip:)];
		
		
		
	} else if ([itemIdent isEqual: ShowQueueIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
		
        // Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: @"Show Queue"];
		[toolbarItem setPaletteLabel: @"Show Queue"];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: @"Show Queue"];
		[toolbarItem setImage: [NSImage imageNamed: @"Brushed Window"]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(ShowQueuePanel:)];
		
	} else if ([itemIdent isEqual: AddToQueueIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
		
        // Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: @"Add to Queue"];
		[toolbarItem setPaletteLabel: @"Add to Queue"];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: @"Add to Queue"];
		[toolbarItem setImage: [NSImage imageNamed: @"Add"]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(AddToQueue:)];
		
		
	} else if ([itemIdent isEqual: PauseEncodingIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
		
        // Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: @"Pause"];
		[toolbarItem setPaletteLabel: @"Pause Encoding"];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: @"Pause Encoding"];
		[toolbarItem setImage: [NSImage imageNamed: @"Pause"]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(Pause:)];
		
	} else if ([itemIdent isEqual: DebugOutputIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
		
        // Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: @"Activity Window"];
		[toolbarItem setPaletteLabel: @"Show Activity Window"];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: @"Show Activity Window"];
		[toolbarItem setImage: [NSImage imageNamed: @"Terminal"]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showDebugOutputPanel:)];
        
		} else if ([itemIdent isEqual: ChooseSourceIdentifier]) {
         toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];

         // Set the text label to be displayed in the toolbar and customization palette 
                [toolbarItem setLabel: @"Source"];
                [toolbarItem setPaletteLabel: @"Source"];
 
                // Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
                [toolbarItem setToolTip: @"Choose Video Source"];
                [toolbarItem setImage: [NSImage imageNamed: @"Disc"]];
 
                // Tell the item what message to send when it is clicked 
                [toolbarItem setTarget: self];
                [toolbarItem setAction: @selector(ShowScanPanel:)];
	
    } else {
        //itemIdent refered to a toolbar item that is not provide or supported by us or cocoa 
        //Returning nil will inform the toolbar this kind of item is not supported 
		toolbarItem = nil;
    }
	
    return toolbarItem;
}

- (void) toggleDrawer {
    [fPresetDrawer toggle:self];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    // Required delegate method:  Returns the ordered list of items to be shown in the toolbar by default    
    // If during the toolbar's initialization, no overriding values are found in the user defaults, or if the
    // user chooses to revert to the default items this set will be used 
    return [NSArray arrayWithObjects: ChooseSourceIdentifier, NSToolbarSeparatorItemIdentifier, StartEncodingIdentifier, PauseEncodingIdentifier,
		AddToQueueIdentifier, ShowQueueIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier, 
		NSToolbarSpaceItemIdentifier, DebugOutputIdentifier, ToggleDrawerIdentifier, nil];
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    // Required delegate method:  Returns the list of all allowed items by identifier.  By default, the toolbar 
    // does not assume any items are allowed, even the separator.  So, every allowed item must be explicitly listed   
    // The set of allowed items is used to construct the customization palette 
    return [NSArray arrayWithObjects:  StartEncodingIdentifier, PauseEncodingIdentifier, AddToQueueIdentifier, ShowQueueIdentifier,
		DebugOutputIdentifier, NSToolbarCustomizeToolbarItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier, NSToolbarSpaceItemIdentifier, ChooseSourceIdentifier,
		NSToolbarSeparatorItemIdentifier,ToggleDrawerIdentifier, nil];
}

- (BOOL) validateToolbarItem: (NSToolbarItem *) toolbarItem {
    // Optional method:  This message is sent to us since we are the target of some toolbar item actions 
    BOOL enable = NO;
    if ([[toolbarItem itemIdentifier] isEqual: ToggleDrawerIdentifier]) {
		enable = YES;
	}
	if ([[toolbarItem itemIdentifier] isEqual: StartEncodingIdentifier]) {
		enable = startButtonEnabled;
		if(stopOrStart) {
			[toolbarItem setImage: [NSImage imageNamed: @"Stop"]];
			[toolbarItem setLabel: @"Cancel"];
			[toolbarItem setPaletteLabel: @"Cancel"];
			[toolbarItem setToolTip: @"Cancel Encoding"];
		}
		else {
			[toolbarItem setImage: [NSImage imageNamed: @"Play"]];
			[toolbarItem setLabel: @"Start"];
			[toolbarItem setPaletteLabel: @"Start Encoding"];
			[toolbarItem setToolTip: @"Start Encoding"];
		}
		
	}
	if ([[toolbarItem itemIdentifier] isEqual: PauseEncodingIdentifier]) {
		enable = pauseButtonEnabled;
		if(resumeOrPause) {
			[toolbarItem setImage: [NSImage imageNamed: @"Play"]];
			[toolbarItem setLabel: @"Resume"];
			[toolbarItem setPaletteLabel: @"Resume Encoding"];
			[toolbarItem setToolTip: @"Resume Encoding"];
		}
		else {
			[toolbarItem setImage: [NSImage imageNamed: @"Pause"]];
			[toolbarItem setLabel: @"Pause"];
			[toolbarItem setPaletteLabel: @"Pause Encoding"];
			[toolbarItem setToolTip: @"Pause Encoding"];
		}
	}
	if ([[toolbarItem itemIdentifier] isEqual: DebugOutputIdentifier]) {
		enable = YES;
	}
	if ([[toolbarItem itemIdentifier] isEqual: ShowQueueIdentifier]) {
		enable = YES;
	}
	if ([[toolbarItem itemIdentifier] isEqual: AddToQueueIdentifier]) {
		enable = AddToQueueButtonEnabled;
	}
	if ([[toolbarItem itemIdentifier] isEqual: ChooseSourceIdentifier]) {
        enable = YES;
    }    
	return enable;
}

// register a test notification and make
// it enabled by default
#define SERVICE_NAME @"Encode Done"
- (NSDictionary *)registrationDictionaryForGrowl 
{ 
NSDictionary *registrationDictionary = [NSDictionary dictionaryWithObjectsAndKeys: 
[NSArray arrayWithObjects:SERVICE_NAME,nil], GROWL_NOTIFICATIONS_ALL, 
[NSArray arrayWithObjects:SERVICE_NAME,nil], GROWL_NOTIFICATIONS_DEFAULT, 
nil]; 

return registrationDictionary; 
} 
- (void) TranslateStrings
{
    [fSrcDVD1Field      setStringValue: _( @"DVD:" )];
    [fSrcTitleField     setStringValue: _( @"Title:" )];
    [fSrcChapterField   setStringValue: _( @"Chapters:" )];
    [fSrcChapterToField setStringValue: _( @"to" )];
    [fSrcDuration1Field setStringValue: _( @"Duration:" )];

    [fDstFormatField    setStringValue: _( @"File format:" )];
    [fDstCodecsField    setStringValue: _( @"Codecs:" )];
    [fDstFile1Field     setStringValue: _( @"File:" )];
    [fDstBrowseButton   setTitle:       _( @"Browse" )];

    [fVidRateField      setStringValue: _( @"Framerate (fps):" )];
    [fVidEncoderField   setStringValue: _( @"Encoder:" )];
    [fVidQualityField   setStringValue: _( @"Quality:" )];
}

/***********************************************************************
 * UpdateDockIcon
 ***********************************************************************
 * Shows a progression bar on the dock icon, filled according to
 * 'progress' (0.0 <= progress <= 1.0).
 * Called with progress < 0.0 or progress > 1.0, restores the original
 * icon.
 **********************************************************************/
- (void) UpdateDockIcon: (float) progress
{
    NSImage * icon;
    NSData * tiff;
    NSBitmapImageRep * bmp;
    uint32_t * pen;
    uint32_t black = htonl( 0x000000FF );
    uint32_t red   = htonl( 0xFF0000FF );
    uint32_t white = htonl( 0xFFFFFFFF );
    int row_start, row_end;
    int i, j;

    /* Get application original icon */
    icon = [NSImage imageNamed: @"NSApplicationIcon"];

    if( progress < 0.0 || progress > 1.0 )
    {
        [NSApp setApplicationIconImage: icon];
        return;
    }

    /* Get it in a raw bitmap form */
    tiff = [icon TIFFRepresentationUsingCompression:
            NSTIFFCompressionNone factor: 1.0];
    bmp = [NSBitmapImageRep imageRepWithData: tiff];
    
    /* Draw the progression bar */
    /* It's pretty simple (ugly?) now, but I'm no designer */

    row_start = 3 * (int) [bmp size].height / 4;
    row_end   = 7 * (int) [bmp size].height / 8;

    for( i = row_start; i < row_start + 2; i++ )
    {
        pen = (uint32_t *) ( [bmp bitmapData] + i * [bmp bytesPerRow] );
        for( j = 0; j < (int) [bmp size].width; j++ )
        {
            pen[j] = black;
        }
    }
    for( i = row_start + 2; i < row_end - 2; i++ )
    {
        pen = (uint32_t *) ( [bmp bitmapData] + i * [bmp bytesPerRow] );
        pen[0] = black;
        pen[1] = black;
        for( j = 2; j < (int) [bmp size].width - 2; j++ )
        {
            if( j < 2 + (int) ( ( [bmp size].width - 4.0 ) * progress ) )
            {
                pen[j] = red;
            }
            else
            {
                pen[j] = white;
            }
        }
        pen[j]   = black;
        pen[j+1] = black;
    }
    for( i = row_end - 2; i < row_end; i++ )
    {
        pen = (uint32_t *) ( [bmp bitmapData] + i * [bmp bytesPerRow] );
        for( j = 0; j < (int) [bmp size].width; j++ )
        {
            pen[j] = black;
        }
    }

    /* Now update the dock icon */
    tiff = [bmp TIFFRepresentationUsingCompression:
            NSTIFFCompressionNone factor: 1.0];
    icon = [[NSImage alloc] initWithData: tiff];
    [NSApp setApplicationIconImage: icon];
    [icon release];
}

- (void) UpdateUI: (NSTimer *) timer
{

hb_list_t  * list;
list = hb_get_titles( fHandle );	
    /* check to see if there has been a new scan done
	this bypasses the constraints of HB_STATE_WORKING
	not allowing setting a newly scanned source */
	int checkScanCount = hb_get_scancount( fHandle );
	if (checkScanCount > currentScanCount)
	{

		currentScanCount = checkScanCount;
			[fScanController Cancel: NULL];
		    [fScanIndicator setIndeterminate: NO];
            [fScanIndicator setDoubleValue: 0.0];
			[fScanIndicator setHidden: YES];
			[fScanController Cancel: NULL];
			[self ShowNewScan: NULL];

	}
	
	
	
	
    hb_state_t s;
    hb_get_state( fHandle, &s );
	
	
    switch( s.state )
    {
        case HB_STATE_IDLE:
            break;
#define p s.param.scanning			
        case HB_STATE_SCANNING:
		{
            [fSrcDVD2Field setStringValue: [NSString stringWithFormat:
                _( @"Scanning title %d of %d..." ),
                p.title_cur, p.title_count]];
            [fScanIndicator setIndeterminate: NO];
			[fScanIndicator setDoubleValue: 100.0 * ( p.title_cur - 1 ) /
                p.title_count];
            break;
		}
#undef p
	
#define p s.param.scandone
        case HB_STATE_SCANDONE:
        {
			
			[fScanIndicator setIndeterminate: NO];
            [fScanIndicator setDoubleValue: 0.0];
			[fScanIndicator setHidden: YES];
			[fScanController Cancel: NULL];
			[self ShowNewScan: NULL];
			break;
        }
#undef p
			
#define p s.param.working
        case HB_STATE_WORKING:
        {
            float progress_total;
            NSMutableString * string;
			/* Currently, p.job_cur and p.job_count get screwed up when adding
				jobs during encoding, if they cannot be fixed in libhb, will implement a
				nasty but working cocoa solution */
			/* Update text field */
			string = [NSMutableString stringWithFormat: _( @"Encoding: task %d of %d, %.2f %%" ), p.job_cur, p.job_count, 100.0 * p.progress];
            
			if( p.seconds > -1 )
            {
                [string appendFormat:
                    _( @" (%.2f fps, avg %.2f fps, ETA %02dh%02dm%02ds)" ),
                    p.rate_cur, p.rate_avg, p.hours, p.minutes, p.seconds];
            }
            [fStatusField setStringValue: string];
			
            /* Update slider */
			progress_total = ( p.progress + p.job_cur - 1 ) / p.job_count;
            [fRipIndicator setIndeterminate: NO];
            [fRipIndicator setDoubleValue: 100.0 * progress_total];
			
            /* Update dock icon */
            [self UpdateDockIcon: progress_total];
			
            /* new toolbar controls */
            pauseButtonEnabled = YES;
            resumeOrPause = NO;
            startButtonEnabled = YES;
            stopOrStart = YES;			
			
            break;
        }
#undef p
			
#define p s.param.muxing
        case HB_STATE_MUXING:
        {
            NSMutableString * string;
			
            /* Update text field */
            string = [NSMutableString stringWithFormat:
                _( @"Muxing..." )];
            [fStatusField setStringValue: string];
			
            /* Update slider */
            [fRipIndicator setIndeterminate: YES];
            [fRipIndicator startAnimation: nil];
			
            /* Update dock icon */
            [self UpdateDockIcon: 1.0];
			
            //[fPauseButton setEnabled: YES];
            //[fPauseButton setTitle: _( @"Pause" )];
            //[fRipButton setEnabled: YES];
			// [fRipButton setTitle: _( @"Cancel" )];
            break;
        }
#undef p
			
        case HB_STATE_PAUSED:
		    //[fStatusField setStringValue: _( @"Paused" )];
            //[fPauseButton setEnabled: YES];
            //[fPauseButton setTitle: _( @"Resume" )];
            //[fRipButton setEnabled: YES];
            //[fRipButton setTitle: _( @"Cancel" )];
			/* new toolbar controls */
            pauseButtonEnabled = YES;
            resumeOrPause = YES;
            startButtonEnabled = YES;
            stopOrStart = YES;
            break;
			
        case HB_STATE_WORKDONE:
        {
            [fStatusField setStringValue: _( @"Done." )];
            [fRipIndicator setIndeterminate: NO];
            [fRipIndicator setDoubleValue: 0.0];
            //[fRipButton setTitle: _( @"Start" )];
			
            /* Restore dock icon */
            [self UpdateDockIcon: -1.0];
			
            //[fPauseButton setEnabled: NO];
            //[fPauseButton setTitle: _( @"Pause" )];
			// [fRipButton setEnabled: YES];
			// [fRipButton setTitle: _( @"Start" )];
			/* new toolbar controls */
            pauseButtonEnabled = NO;
            resumeOrPause = NO;
            startButtonEnabled = YES;
            stopOrStart = NO;
			NSRect frame = [fWindow frame];
			if (frame.size.width <= 591)
				frame.size.width = 591;
			frame.size.height += -44;
			frame.origin.y -= -44;
			[fWindow setFrame:frame display:YES animate:YES];
			
            /* FIXME */
            hb_job_t * job;
            while( ( job = hb_job( fHandle, 0 ) ) )
            {
                hb_rem( fHandle, job );
            }
            /* Check to see if the encode state has not been cancelled
				to determine if we should check for encode done notifications */
			if (fEncodeState != 2) 			{
				/* If Growl Notification or Window and Growl has been selected */
				if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"AlertWhenDone"] isEqualToString: @"Growl Notification"] || 
					[[[NSUserDefaults standardUserDefaults] stringForKey:@"AlertWhenDone"] isEqualToString: @"Alert Window And Growl"])
                {
					/*Growl Notification*/
					[self showGrowlDoneNotification: NULL];
                }
                /* If Alert Window or Window and Growl has been selected */
				if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"AlertWhenDone"] isEqualToString: @"Alert Window"] || 
					[[[NSUserDefaults standardUserDefaults] stringForKey:@"AlertWhenDone"] isEqualToString: @"Alert Window And Growl"])
                {
					/*On Screen Notification*/
					int status;
					NSBeep();
					status = NSRunAlertPanel(@"Put down that cocktail...",@"your HandBrake encode is done!", @"OK", nil, nil);
					[NSApp requestUserAttention:NSCriticalRequest];
					if ( status == NSAlertDefaultReturn ) 
					{
						[self EnableUI: YES];
					}
                }
				else
				{
					[self EnableUI: YES];
				}
			           /* If sleep has been selected */ 
            if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"AlertWhenDone"] isEqualToString: @"Put Computer To Sleep"]) 
                { 
               /* Sleep */ 
               NSDictionary* errorDict; 
               NSAppleEventDescriptor* returnDescriptor = NULL; 
               NSAppleScript* scriptObject = [[NSAppleScript alloc] initWithSource: 
                        @"tell application \"Finder\" to sleep"]; 
               returnDescriptor = [scriptObject executeAndReturnError: &errorDict]; 
               [scriptObject release]; 
               [self EnableUI: YES]; 
                } 
            /* If Shutdown has been selected */ 
            if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"AlertWhenDone"] isEqualToString: @"Shut Down Computer"]) 
                { 
               /* Shut Down */ 
               NSDictionary* errorDict; 
               NSAppleEventDescriptor* returnDescriptor = NULL; 
               NSAppleScript* scriptObject = [[NSAppleScript alloc] initWithSource: 
                        @"tell application \"Finder\" to shut down"]; 
               returnDescriptor = [scriptObject executeAndReturnError: &errorDict]; 
               [scriptObject release]; 
               [self EnableUI: YES]; 
                }
			
			}
			else
			{
				[self EnableUI: YES];
			}
            break;
        }
    }
	
    /* Lets show the queue status
		here in the main window*/
	int queue_count = hb_count( fHandle );
	if( queue_count )
	{
		[fQueueStatus setStringValue: [NSString stringWithFormat:
			@"%d task%s in the queue",
						 queue_count, ( queue_count > 1 ) ? "s" : ""]];
	}
	else
	{
		[fQueueStatus setStringValue: @""];
	}
	
    [[NSRunLoop currentRunLoop] addTimer: [NSTimer
        scheduledTimerWithTimeInterval: 0.5 target: self
							  selector: @selector( UpdateUI: ) userInfo: NULL repeats: FALSE]
								 forMode: NSModalPanelRunLoopMode];
}
- (IBAction) ShowNewScan:(id)sender
{
	hb_list_t  * list;
	hb_title_t * title;
	int indxpri=0; 	  // Used to search the longuest title (default in combobox)
	int longuestpri=0; // Used to search the longuest title (default in combobox)
	
	list = hb_get_titles( fHandle );
	
	if( !hb_list_count( list ) )
	{
		/* We display a message if a valid dvd source was not chosen */
		if (sourceDisplayName)
		{
		/* Temporary string if til restoring old source is fixed */
		[fSrcDVD2Field setStringValue: @"Not A Valid Source"];
		//[fSrcDVD2Field setStringValue: [NSString stringWithFormat: @"%s", sourceDisplayName]];
		}
		else
		{
	    [fSrcDVD2Field setStringValue: @"No Valid Title Found"];
		}	
	}
	else
	{
		
		[fSrcTitlePopUp removeAllItems];
		for( int i = 0; i < hb_list_count( list ); i++ )
		{
			title = (hb_title_t *) hb_list_item( list, i );
			/*Set DVD Name at top of window*/
			[fSrcDVD2Field setStringValue:[NSString stringWithUTF8String: title->name]];
			
			currentSource = [NSString stringWithUTF8String: title->dvd];
			
			
			/* Use the dvd name in the default output field here 
				May want to add code to remove blank spaces for some dvd names*/
			/* Check to see if the last destination has been set,use if so, if not, use Desktop */
			if ([[NSUserDefaults standardUserDefaults] stringForKey:@"LastDestinationDirectory"])
			{
				[fDstFile2Field setStringValue: [NSString stringWithFormat:
					@"%@/%@.mp4", [[NSUserDefaults standardUserDefaults] stringForKey:@"LastDestinationDirectory"],[NSString
                  stringWithUTF8String: title->name]]];
			}
			else
			{
				[fDstFile2Field setStringValue: [NSString stringWithFormat:
					@"%@/Desktop/%@.mp4", NSHomeDirectory(),[NSString
                  stringWithUTF8String: title->name]]];
			}
			
			
			if (longuestpri < title->hours*60*60 + title->minutes *60 + title->seconds)
			{
				longuestpri=title->hours*60*60 + title->minutes *60 + title->seconds;
				indxpri=i;
			}
			
			
			int format = [fDstFormatPopUp indexOfSelectedItem];
			char * ext = NULL;
			switch( format )
			{
				case 0:
					
					/*Get Default MP4 File Extension for mpeg4 (.mp4 or .m4v) from prefs*/
					if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultMpegName"] > 0)
					{
						ext = "m4v";
					}
					else
					{
						ext = "mp4";
					}
					break;
				case 1: 
					ext = "avi";
					break;
				case 2:
					ext = "ogm";
					break;
			}
			
			
			NSString * string = [fDstFile2Field stringValue];
			/* Add/replace File Output name to the correct extension*/
			if( [string characterAtIndex: [string length] - 4] == '.' )
			{
				[fDstFile2Field setStringValue: [NSString stringWithFormat:
					@"%@.%s", [string substringToIndex: [string length] - 4],
					ext]];
			}
			else
			{
				[fDstFile2Field setStringValue: [NSString stringWithFormat:
					@"%@.%s", string, ext]];
			}
			
			
			[fSrcTitlePopUp addItemWithTitle: [NSString
                    stringWithFormat: @"%d - %02dh%02dm%02ds",
				title->index, title->hours, title->minutes,
				title->seconds]];
			
		}
		// Select the longuest title
		[fSrcTitlePopUp selectItemAtIndex: indxpri];
		/* We set the Settings Display to "Default" here
			until we get default presets implemented */
		[fPresetSelectedDisplay setStringValue: @"Default"];
		/* We set the auto crop in the main window to value "1" just as in PictureController,
			as it does not seem to be taken from any job-> variable */
		[fPicSettingAutoCrop setStringValue: [NSString stringWithFormat:
			@"%d", 1]];
		
		[self TitlePopUpChanged: NULL];
		[self EnableUI: YES];
		//[fPauseButton setEnabled: NO];
		//[fRipButton   setEnabled: YES];
		startButtonEnabled = YES;
		stopOrStart = NO;
		AddToQueueButtonEnabled = YES;
		pauseButtonEnabled = NO;
		resumeOrPause = NO;
		/* we record the current source name here in case the next scan is unsuccessful,
				then we can replace the scan progress with the old name if necessary */
			sourceDisplayName = [NSString stringWithFormat:[fSrcDVD2Field stringValue]];
	}
}


-(IBAction)showGrowlDoneNotification:(id)sender
{

  
  [GrowlApplicationBridge 
          notifyWithTitle:@"Put down that cocktail..." 
              description:@"your HandBrake encode is done!" 
         notificationName:SERVICE_NAME
                 iconData:nil 
                 priority:0 
                 isSticky:1 
             clickContext:nil];
}
- (void) EnableUI: (bool) b
{
    NSControl * controls[] =
      { fSrcDVD1Field, fSrcTitleField, fSrcTitlePopUp,
        fSrcChapterField, fSrcChapterStartPopUp, fSrcChapterToField,
        fSrcChapterEndPopUp, fSrcDuration1Field, fSrcDuration2Field,
        fDstFormatField, fDstFormatPopUp, fDstCodecsField,
        fDstCodecsPopUp, fDstFile1Field, fDstFile2Field,
        fDstBrowseButton, fVidRateField, fVidRatePopUp,
        fVidEncoderField, fVidEncoderPopUp, fVidQualityField,
        fVidQualityMatrix, fVidGrayscaleCheck, fSubField, fSubPopUp,
        fAudLang1Field, fAudLang1PopUp, fAudLang2Field, fAudLang2PopUp,
        fAudTrack1MixLabel, fAudTrack1MixPopUp, fAudTrack2MixLabel, fAudTrack2MixPopUp,
        fAudRateField, fAudRatePopUp, fAudBitrateField,
        fAudBitratePopUp, fPictureButton,fQueueStatus, 
		fPicSrcWidth,fPicSrcHeight,fPicSettingWidth,fPicSettingHeight,
		fPicSettingARkeep,fPicSettingDeinterlace,fPicSettingARkeepDsply,
		fPicSettingDeinterlaceDsply,fPicLabelSettings,fPicLabelSrc,fPicLabelOutp,
		fPicLabelAr,fPicLabelDeinter,fPicLabelSrcX,fPicLabelOutputX,
		fPicLabelPAROutp,fPicLabelPAROutputX,fPicSettingPARWidth,fPicSettingPARHeight,
		fPicSettingPARDsply,fPicLabelAnamorphic,tableView,fPresetsAdd,fPresetsDelete,
		fCreateChapterMarkers,fX264optViewTitleLabel,fDisplayX264Options,fDisplayX264OptionsLabel,fX264optBframesLabel,
		fX264optBframesPopUp,fX264optRefLabel,fX264optRefPopUp,fX264optNfpskipLabel,fX264optNfpskipSwitch,
		fX264optNodctdcmtLabel,fX264optNodctdcmtSwitch,fX264optSubmeLabel,fX264optSubmePopUp,
		fX264optTrellisLabel,fX264optTrellisPopUp,fX264optMixedRefsLabel,fX264optMixedRefsSwitch,
		fX264optMotionEstLabel,fX264optMotionEstPopUp,fX264optMERangeLabel,fX264optMERangePopUp,
		fX264optWeightBLabel,fX264optWeightBSwitch,fX264optBRDOLabel,fX264optBRDOSwitch,
		fX264optBPyramidLabel,fX264optBPyramidSwitch,fX264optBiMELabel,fX264optBiMESwitch,
		fX264optDirectPredLabel,fX264optDirectPredPopUp,fX264optDeblockLabel,fX264optAnalyseLabel,
		fX264optAnalysePopUp,fX264opt8x8dctLabel,fX264opt8x8dctSwitch,fX264optCabacLabel,fX264optCabacSwitch,
		fX264optAlphaDeblockPopUp,fX264optBetaDeblockPopUp,fVidTurboPassCheck,fDstMpgLargeFileCheck,fPicSettingAutoCropLabel,
		fPicSettingAutoCropDsply};

    for( unsigned i = 0;
         i < sizeof( controls ) / sizeof( NSControl * ); i++ )
    {
        if( [[controls[i] className] isEqualToString: @"NSTextField"] )
        {
            NSTextField * tf = (NSTextField *) controls[i];
            if( ![tf isBezeled] )
            {
                [tf setTextColor: b ? [NSColor controlTextColor] :
                    [NSColor disabledControlTextColor]];
                continue;
            }
        }
        [controls[i] setEnabled: b];

    }
	
	if (b) {

        /* if we're enabling the interface, check if the audio mixdown controls need to be enabled or not */
        /* these will have been enabled by the mass control enablement above anyway, so we're sense-checking it here */
        [self SetEnabledStateOfAudioMixdownControls: NULL];
	
	} else {

		[tableView setEnabled: NO];
	
	}

    [self VideoMatrixChanged: NULL];
}

- (IBAction) ShowScanPanel: (id) sender
{
    [fScanController Show];
}

- (IBAction) OpenMainWindow: (id) sender
{
[fWindow  makeKeyAndOrderFront:nil];
[fWindow setReleasedWhenClosed: YES];
}
- (BOOL) windowShouldClose: (id) sender
{

	/* See if we are currently running */
	hb_state_t s;
	hb_get_state( fHandle, &s );
	if ( s.state ==  HB_STATE_WORKING)
	{
	   /* If we are running, leave in memory when closing main window */
	   [fWindow setReleasedWhenClosed: NO];
	   return YES;

	}
	else
	{
		/* Stop the application when the user closes the window */
		[NSApp terminate: self];
		return YES;
	}
	
}

- (IBAction) VideoMatrixChanged: (id) sender;
{
    bool target, bitrate, quality;

    target = bitrate = quality = false;
    if( [fVidQualityMatrix isEnabled] )
    {
        switch( [fVidQualityMatrix selectedRow] )
        {
            case 0:
                target = true;
                break;
            case 1:
                bitrate = true;
                break;
            case 2:
                quality = true;
                break;
        }
    }
    [fVidTargetSizeField  setEnabled: target];
    [fVidBitrateField     setEnabled: bitrate];
    [fVidQualitySlider    setEnabled: quality];
    [fVidTwoPassCheck     setEnabled: !quality &&
        [fVidQualityMatrix isEnabled]];
    if( quality )
    {
        [fVidTwoPassCheck setState: NSOffState];
    }

    [self QualitySliderChanged: sender];
    [self CalculateBitrate:     sender];
	[self CustomSettingUsed: sender];
}

- (IBAction) QualitySliderChanged: (id) sender
{
    [fVidConstantCell setTitle: [NSString stringWithFormat:
        _( @"Constant quality: %.0f %%" ), 100.0 *
        [fVidQualitySlider floatValue]]];
		[self CustomSettingUsed: sender];
}

- (IBAction) BrowseFile: (id) sender
{
    /* Open a panel to let the user choose and update the text field */
    NSSavePanel * panel = [NSSavePanel savePanel];
	/* We get the current file name and path from the destination field here */
	[panel beginSheetForDirectory: [[fDstFile2Field stringValue] stringByDeletingLastPathComponent] file: [[fDstFile2Field stringValue] lastPathComponent]
				   modalForWindow: fWindow modalDelegate: self
				   didEndSelector: @selector( BrowseFileDone:returnCode:contextInfo: )
					  contextInfo: NULL];
}

- (void) BrowseFileDone: (NSSavePanel *) sheet
    returnCode: (int) returnCode contextInfo: (void *) contextInfo
{
    if( returnCode == NSOKButton )
    {
        [fDstFile2Field setStringValue: [sheet filename]];
		
    }
}

- (IBAction) ShowPicturePanel: (id) sender
{
    hb_list_t  * list  = hb_get_titles( fHandle );
    hb_title_t * title = (hb_title_t *) hb_list_item( list,
            [fSrcTitlePopUp indexOfSelectedItem] );

    /* Resize the panel */
    NSSize newSize;
    newSize.width  = 246 + title->width;
    newSize.height = 80 + title->height;
    [fPicturePanel setContentSize: newSize];

    [fPictureController SetTitle: title];

    [NSApp beginSheet: fPicturePanel modalForWindow: fWindow
        modalDelegate: NULL didEndSelector: NULL contextInfo: NULL];
    [NSApp runModalForWindow: fPicturePanel];
    [NSApp endSheet: fPicturePanel];
    [fPicturePanel orderOut: self];
	[self CalculatePictureSizing: sender];
}

- (IBAction) ShowQueuePanel: (id) sender
{
    /* Update the OutlineView */
    [fQueueController Update: sender];

    /* Show the panel */
    [NSApp beginSheet: fQueuePanel modalForWindow: fWindow
        modalDelegate: NULL didEndSelector: NULL contextInfo: NULL];
    [NSApp runModalForWindow: fQueuePanel];
    [NSApp endSheet: fQueuePanel];
    [fQueuePanel orderOut: self];
}

- (void) PrepareJob
{
    hb_list_t  * list  = hb_get_titles( fHandle );
    hb_title_t * title = (hb_title_t *) hb_list_item( list,
            [fSrcTitlePopUp indexOfSelectedItem] );
    hb_job_t * job = title->job;
    //int i;

    /* Chapter selection */
    job->chapter_start = [fSrcChapterStartPopUp indexOfSelectedItem] + 1;
    job->chapter_end   = [fSrcChapterEndPopUp   indexOfSelectedItem] + 1;
	
    /* Format and codecs */
    int format = [fDstFormatPopUp indexOfSelectedItem];
    int codecs = [fDstCodecsPopUp indexOfSelectedItem];
    job->mux    = FormatSettings[format][codecs] & HB_MUX_MASK;
    job->vcodec = FormatSettings[format][codecs] & HB_VCODEC_MASK;
    job->acodec = FormatSettings[format][codecs] & HB_ACODEC_MASK;
    /* If mpeg-4, then set mpeg-4 specific options like chapters and > 4gb file sizes */
	if ([fDstFormatPopUp indexOfSelectedItem] == 0)
	{
        /* We set the chapter marker extraction here based on the format being
		mpeg4 and the checkbox being checked */
		if ([fCreateChapterMarkers state] == NSOnState)
		{
			job->chapter_markers = 1;
		}
		else
		{
			job->chapter_markers = 0;
		}
		/* We set the largeFileSize (64 bit formatting) variable here to allow for > 4gb files based on the format being
		mpeg4 and the checkbox being checked 
		*Note: this will break compatibility with some target devices like iPod, etc.!!!!*/
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AllowLargeFiles"] > 0 && [fDstMpgLargeFileCheck state] == NSOnState)
		{
			job->largeFileSize = 1;
		}
		else
		{
			job->largeFileSize = 0;
		}
	}
	
	
	if( ( job->vcodec & HB_VCODEC_FFMPEG ) &&
        [fVidEncoderPopUp indexOfSelectedItem] > 0 )
    {
        job->vcodec = HB_VCODEC_XVID;
    }
    if( job->vcodec & HB_VCODEC_X264 )
    {
		if ([fVidEncoderPopUp indexOfSelectedItem] > 0 )
	    {
			/* Just use new Baseline Level 3.0 
			Lets Deprecate Baseline Level 1.3h264_level*/
			job->h264_level = 30;
			job->mux = HB_MUX_IPOD;
			/* move sanity check for iPod Encoding here */
			job->pixel_ratio = 0 ;
			
		}
		
		/* Set this flag to switch from Constant Quantizer(default) to Constant Rate Factor Thanks jbrjake
		Currently only used with Constant Quality setting*/
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultCrf"] > 0 && [fVidQualityMatrix selectedRow] == 2)
		{
	        job->crf = 1;
		}
		
		/* Below Sends x264 options to the core library if x264 is selected*/
		/* Lets use this as per Nyx, Thanks Nyx!*/
		job->x264opts = (char *)calloc(1024, 1); /* Fixme, this just leaks */
		/* Turbo first pass if two pass and Turbo First pass is selected */
		if( [fVidTwoPassCheck state] == NSOnState && [fVidTurboPassCheck state] == NSOnState )
		{
			/* pass the "Turbo" string to be appended to the existing x264 opts string into a variable for the first pass */
			NSString *firstPassOptStringTurbo = @":ref=1:subme=1:me=dia:analyse=none:weightb=0:trellis=0:no-fast-pskip=0:8x8dct=0";
			/* append the "Turbo" string variable to the existing opts string.
			Note: the "Turbo" string must be appended, not prepended to work properly*/
			NSString *firstPassOptStringCombined = [[fDisplayX264Options stringValue] stringByAppendingString:firstPassOptStringTurbo];
			strcpy(job->x264opts, [firstPassOptStringCombined UTF8String]);
		}
		else
		{
			strcpy(job->x264opts, [[fDisplayX264Options stringValue] UTF8String]);
		}
		
        job->h264_13 = [fVidEncoderPopUp indexOfSelectedItem];
    }

    /* Video settings */
    if( [fVidRatePopUp indexOfSelectedItem] > 0 )
    {
        job->vrate      = 27000000;
        job->vrate_base = hb_video_rates[[fVidRatePopUp
            indexOfSelectedItem]-1].rate;
    }
    else
    {
        job->vrate      = title->rate;
        job->vrate_base = title->rate_base;
    }

    switch( [fVidQualityMatrix selectedRow] )
    {
        case 0:
            /* Target size.
               Bitrate should already have been calculated and displayed
               in fVidBitrateField, so let's just use it */
        case 1:
            job->vquality = -1.0;
            job->vbitrate = [fVidBitrateField intValue];
            break;
        case 2:
            job->vquality = [fVidQualitySlider floatValue];
            job->vbitrate = 0;
            break;
    }

    job->grayscale = ( [fVidGrayscaleCheck state] == NSOnState );
    


    /* Subtitle settings */
    job->subtitle = [fSubPopUp indexOfSelectedItem] - 1;

    /* Audio tracks and mixdowns */
    /* check for the condition where track 2 has an audio selected, but track 1 does not */
    /* we will use track 2 as track 1 in this scenario */
    if ([fAudLang1PopUp indexOfSelectedItem] > 0)
    {
        job->audios[0] = [fAudLang1PopUp indexOfSelectedItem] - 1;
        job->audios[1] = [fAudLang2PopUp indexOfSelectedItem] - 1; /* will be -1 if "none" is selected */
        job->audios[2] = -1;
        job->audio_mixdowns[0] = [[fAudTrack1MixPopUp selectedItem] tag];
        job->audio_mixdowns[1] = [[fAudTrack2MixPopUp selectedItem] tag];
    }
    else if ([fAudLang2PopUp indexOfSelectedItem] > 0)
    {
        job->audios[0] = [fAudLang2PopUp indexOfSelectedItem] - 1;
        job->audio_mixdowns[0] = [[fAudTrack2MixPopUp selectedItem] tag];
        job->audios[1] = -1;
    }
    else
    {
        job->audios[0] = -1;
    }

    /* Audio settings */
    job->arate = hb_audio_rates[[fAudRatePopUp
                     indexOfSelectedItem]].rate;
    job->abitrate = [[fAudBitratePopUp selectedItem] tag];
    
    /* TODO: Filter settings */ 
    job->filters = hb_list_init();
#if 1
    /* Run old deinterlacer if deinterlacing specified */
    if( job->deinterlace )
    {        
        hb_filter_deinterlace.settings = "-1"; 
        hb_list_add( job->filters, &hb_filter_deinterlace );
    }
#else
    /* Choose your own filters! Here's some examples... */
    hb_filter_detelecine.settings = "1:1:4:4:0:0";
    hb_list_add( job->filters, &hb_filter_detelecine );

    hb_filter_deinterlace.settings = "3:-1:2:10";
    hb_list_add( job->filters, &hb_filter_deinterlace );

    hb_filter_deblock.settings = "4:2";
    hb_list_add( job->filters, &hb_filter_deblock );

    hb_filter_denoise.settings = "3:2:3:3";
    hb_list_add( job->filters, &hb_filter_denoise );
#endif     
}



- (IBAction) AddToQueue: (id) sender
{
/* We get the destination directory from the destingation field here */
	NSString *destinationDirectory = [[fDstFile2Field stringValue] stringByDeletingLastPathComponent];
	/* We check for a valid destination here */
	if ([[NSFileManager defaultManager] fileExistsAtPath:destinationDirectory] == 0) 
	{
		NSRunAlertPanel(@"Warning!", @"This is not a valid destination directory!", @"OK", nil, nil);
	}
	else
	{
		
		hb_list_t  * list  = hb_get_titles( fHandle );
		hb_title_t * title = (hb_title_t *) hb_list_item( list,
														  [fSrcTitlePopUp indexOfSelectedItem] );
		hb_job_t * job = title->job;
		
		[self PrepareJob];
		
		/* Destination file */
		job->file = [[fDstFile2Field stringValue] UTF8String];
		
		if( [fVidTwoPassCheck state] == NSOnState )
		{
			job->pass = 1;
			hb_add( fHandle, job );
			job->pass = 2;
			
			job->x264opts = (char *)calloc(1024, 1); /* Fixme, this just leaks */  
			strcpy(job->x264opts, [[fDisplayX264Options stringValue] UTF8String]);
			
			hb_add( fHandle, job );
		}
		else
		{
			job->pass = 0;
			hb_add( fHandle, job );
		}
	
	[[NSUserDefaults standardUserDefaults] setObject:destinationDirectory forKey:@"LastDestinationDirectory"];
	/* Lets try to update stuff, taken from remove in the queue controller */
	[fQueueController performSelectorOnMainThread: @selector( Update: )
        withObject: sender waitUntilDone: NO];
	}
}

- (IBAction) Rip: (id) sender
{
    /* Rip or Cancel ? */
 //   if( [[fRipButton title] isEqualToString: _( @"Cancel" )] )
    if(stopOrStart)
	{
        [self Cancel: sender];
        return;
    }
	/* if there is no job in the queue, then add it to the queue and rip 
	otherwise, there are already jobs in queue, so just rip the queue */
	int count = hb_count( fHandle );
	if( count < 1 )
        {
		[self AddToQueue: sender];
		}
    
	    /* We check for duplicate name here */
	if( [[NSFileManager defaultManager] fileExistsAtPath:
            [fDstFile2Field stringValue]] )
    {
        NSBeginCriticalAlertSheet( _( @"File already exists" ),
            _( @"Cancel" ), _( @"Overwrite" ), NULL, fWindow, self,
            @selector( OverwriteAlertDone:returnCode:contextInfo: ),
            NULL, NULL, [NSString stringWithFormat:
            _( @"Do you want to overwrite %@?" ),
            [fDstFile2Field stringValue]] );
        return;
    }
	/* We get the destination directory from the destination field here */
	NSString *destinationDirectory = [[fDstFile2Field stringValue] stringByDeletingLastPathComponent];
	/* We check for a valid destination here */
	if ([[NSFileManager defaultManager] fileExistsAtPath:destinationDirectory] == 0) 
	{
		NSRunAlertPanel(@"Warning!", @"This is not a valid destination directory!", @"OK", nil, nil);
	}
	else
	{
	[[NSUserDefaults standardUserDefaults] setObject:destinationDirectory forKey:@"LastDestinationDirectory"];
		[self _Rip];
	}
	


}

- (void) OverwriteAlertDone: (NSWindow *) sheet
    returnCode: (int) returnCode contextInfo: (void *) contextInfo
{
    if( returnCode == NSAlertAlternateReturn )
    {
        [self _Rip];
    }
}

- (void) UpdateAlertDone: (NSWindow *) sheet
    returnCode: (int) returnCode contextInfo: (void *) contextInfo
{
    if( returnCode == NSAlertAlternateReturn )
    {
        /* Show scan panel */
        [self performSelectorOnMainThread: @selector(ShowScanPanel:)
            withObject: NULL waitUntilDone: NO];
        return;
    }

    /* Go to HandBrake homepage and exit */
    [self OpenHomepage: NULL];
    [NSApp terminate: self];
}

- (void) _Rip
{
    /* Let libhb do the job */
    hb_start( fHandle );
	/*set the fEncodeState State */
	fEncodeState = 1;
	
    /* Disable interface */
	//[self EnableUI: NO];
	// [fPauseButton setEnabled: NO];
	// [fRipButton   setEnabled: NO];
	pauseButtonEnabled = NO;
	startButtonEnabled = NO;
	NSRect frame = [fWindow frame];
    if (frame.size.width <= 591)
        frame.size.width = 591;
    frame.size.height += 44;
    frame.origin.y -= 44;
    [fWindow setFrame:frame display:YES animate:YES];
}

- (IBAction) Cancel: (id) sender
{
    NSBeginCriticalAlertSheet( _( @"Cancel - Are you sure?" ),
        _( @"Keep working" ), _( @"Cancel encoding" ), NULL, fWindow, self,
        @selector( _Cancel:returnCode:contextInfo: ), NULL, NULL,
        _( @"Encoding won't be recoverable." ) );
}

- (void) _Cancel: (NSWindow *) sheet
    returnCode: (int) returnCode contextInfo: (void *) contextInfo
{
    if( returnCode == NSAlertAlternateReturn )
    {
        hb_stop( fHandle );
       // [fPauseButton setEnabled: NO];
       // [fRipButton   setEnabled: NO];
	   pauseButtonEnabled = NO;
       startButtonEnabled = NO;
		/*set the fEncodeState State */
	     fEncodeState = 2;
    }
}

- (IBAction) Pause: (id) sender
{
   // [fPauseButton setEnabled: NO];
   // [fRipButton   setEnabled: NO];

   // if( [[fPauseButton title] isEqualToString: _( @"Resume" )] )
          pauseButtonEnabled = NO;
       startButtonEnabled = NO;

    if(resumeOrPause)
    {
        hb_resume( fHandle );
    }
    else
    {
        hb_pause( fHandle );
    }
}

- (IBAction) TitlePopUpChanged: (id) sender
{
    hb_list_t  * list  = hb_get_titles( fHandle );
    hb_title_t * title = (hb_title_t*)
        hb_list_item( list, [fSrcTitlePopUp indexOfSelectedItem] );
		
		
    /* If Auto Naming is on. We create an output filename of dvd name - title number */
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultAutoNaming"] > 0)
	{
		[fDstFile2Field setStringValue: [NSString stringWithFormat:
			@"%@/%@-%d.%@", [[fDstFile2Field stringValue] stringByDeletingLastPathComponent],
			[NSString stringWithUTF8String: title->name],
			[fSrcTitlePopUp indexOfSelectedItem] + 1,
			[[fDstFile2Field stringValue] pathExtension]]];	
	}

    /* Update chapter popups */
    [fSrcChapterStartPopUp removeAllItems];
    [fSrcChapterEndPopUp   removeAllItems];
    for( int i = 0; i < hb_list_count( title->list_chapter ); i++ )
    {
        [fSrcChapterStartPopUp addItemWithTitle: [NSString
            stringWithFormat: @"%d", i + 1]];
        [fSrcChapterEndPopUp addItemWithTitle: [NSString
            stringWithFormat: @"%d", i + 1]];
    }
    [fSrcChapterStartPopUp selectItemAtIndex: 0];
    [fSrcChapterEndPopUp   selectItemAtIndex:
        hb_list_count( title->list_chapter ) - 1];
    [self ChapterPopUpChanged: NULL];

/* Start Get and set the initial pic size for display */
	hb_job_t * job = title->job;
	fTitle = title; 
	/* Turn Deinterlace on/off depending on the preference */
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultDeinterlaceOn"] > 0)
	{
		job->deinterlace = 1;
	}
	else
	{
		job->deinterlace = 0;
	}
	
	/* Pixel Ratio Setting */
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"PixelRatio"])
    {

		job->pixel_ratio = 1 ;
	}
	else
	{
		job->pixel_ratio = 0 ;
	}
	/*Set Source Size Fields Here */
	[fPicSrcWidth setStringValue: [NSString stringWithFormat:
							 @"%d", fTitle->width]];
	[fPicSrcHeight setStringValue: [NSString stringWithFormat:
							 @"%d", fTitle->height]];
	/* We get the originial output picture width and height and put them
	in variables for use with some presets later on */
	PicOrigOutputWidth = job->width;
	PicOrigOutputHeight = job->height;
	/* we test getting the max output value for pic sizing here to be used later*/
	[fPicSettingWidth setStringValue: [NSString stringWithFormat:
		@"%d", PicOrigOutputWidth]];
	[fPicSettingHeight setStringValue: [NSString stringWithFormat:
		@"%d", PicOrigOutputHeight]];
	/* we run the picture size values through
	CalculatePictureSizing to get all picture size
	information*/
	[self CalculatePictureSizing: NULL];
	/* Run Through EncoderPopUpChanged to see if there
		needs to be any pic value modifications based on encoder settings */
	//[self EncoderPopUpChanged: NULL];
	/* END Get and set the initial pic size for display */ 

    /* Update subtitle popups */
    hb_subtitle_t * subtitle;
    [fSubPopUp removeAllItems];
    [fSubPopUp addItemWithTitle: @"None"];
    for( int i = 0; i < hb_list_count( title->list_subtitle ); i++ )
    {
        subtitle = (hb_subtitle_t *) hb_list_item( title->list_subtitle, i );

        /* We cannot use NSPopUpButton's addItemWithTitle because
           it checks for duplicate entries */
        [[fSubPopUp menu] addItemWithTitle: [NSString stringWithCString:
            subtitle->lang] action: NULL keyEquivalent: @""];
    }
    [fSubPopUp selectItemAtIndex: 0];
    
    /* Update chapter table */
    [fChapterTitlesDelegate resetWithTitle:title];
    [fChapterTable reloadData];

    /* Update audio popups */
    [self AddAllAudioTracksToPopUp: fAudLang1PopUp];
    [self AddAllAudioTracksToPopUp: fAudLang2PopUp];
    /* search for the first instance of our prefs default language for track 1, and set track 2 to "none" */
	NSString * audioSearchPrefix = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultLanguage"];
    [self SelectAudioTrackInPopUp: fAudLang1PopUp searchPrefixString: audioSearchPrefix selectIndexIfNotFound: 1];
    [self SelectAudioTrackInPopUp: fAudLang2PopUp searchPrefixString: NULL selectIndexIfNotFound: 0];
	
	/* changing the title may have changed the audio channels on offer, */
	/* so call AudioTrackPopUpChanged for both audio tracks to update the mixdown popups */
	[self AudioTrackPopUpChanged: fAudLang1PopUp];
	[self AudioTrackPopUpChanged: fAudLang2PopUp];

}

- (IBAction) ChapterPopUpChanged: (id) sender
{
    
	/* If start chapter popup is greater than end chapter popup,
	we set the end chapter popup to the same as start chapter popup */
	if ([fSrcChapterStartPopUp indexOfSelectedItem] > [fSrcChapterEndPopUp indexOfSelectedItem])
	{
		[fSrcChapterEndPopUp selectItemAtIndex: [fSrcChapterStartPopUp indexOfSelectedItem]];
    }

		
	
	hb_list_t  * list  = hb_get_titles( fHandle );
    hb_title_t * title = (hb_title_t *)
        hb_list_item( list, [fSrcTitlePopUp indexOfSelectedItem] );

    hb_chapter_t * chapter;
    int64_t        duration = 0;
    for( int i = [fSrcChapterStartPopUp indexOfSelectedItem];
         i <= [fSrcChapterEndPopUp indexOfSelectedItem]; i++ )
    {
        chapter = (hb_chapter_t *) hb_list_item( title->list_chapter, i );
        duration += chapter->duration;
    }
    
    duration /= 90000; /* pts -> seconds */
    [fSrcDuration2Field setStringValue: [NSString stringWithFormat:
        @"%02lld:%02lld:%02lld", duration / 3600, ( duration / 60 ) % 60,
        duration % 60]];

    [self CalculateBitrate: sender];
}

- (IBAction) FormatPopUpChanged: (id) sender
{
    NSString * string = [fDstFile2Field stringValue];
    int format = [fDstFormatPopUp indexOfSelectedItem];
    char * ext = NULL;
	/* Initially set the large file (64 bit formatting) output checkbox to hidden */
    [fDstMpgLargeFileCheck setHidden: YES];
    /* Update the codecs popup */
    [fDstCodecsPopUp removeAllItems];
    switch( format )
    {
        case 0:
			/*Get Default MP4 File Extension*/
			if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultMpegName"] > 0)
			{
				ext = "m4v";
			}
			else
			{
				ext = "mp4";
			}
            [fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / AAC Audio" )];
            [fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / AAC Audio" )];
			/* We enable the create chapters checkbox here since we are .mp4*/
			[fCreateChapterMarkers setEnabled: YES];
			/* We show the Large File (64 bit formatting) checkbox since we are .mp4 
			if we have enabled the option in the global preferences*/
			if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AllowLargeFiles"] > 0)
			{
				[fDstMpgLargeFileCheck setHidden: NO];
			}
				else
				{
					/* if not enable in global preferences, we additionaly sanity check that the
					hidden checkbox is set to off. */
					[fDstMpgLargeFileCheck setState: NSOffState];
				}
				break;
        case 1: 
            ext = "avi";
            [fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / MP3 Audio" )];
            [fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / AC-3 Audio" )];
            [fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / MP3 Audio" )];
            [fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / AC-3 Audio" )];
			/* We disable the create chapters checkbox here since we are NOT .mp4 
			and make sure it is unchecked*/
			[fCreateChapterMarkers setEnabled: NO];
			[fCreateChapterMarkers setState: NSOffState];
			break;
        case 2:
            ext = "ogm";
            [fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / Vorbis Audio" )];
            [fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / MP3 Audio" )];
            /* We disable the create chapters checkbox here since we are NOT .mp4 
			and make sure it is unchecked*/
			[fCreateChapterMarkers setEnabled: NO];
			[fCreateChapterMarkers setState: NSOffState];
			break;
		case 3:
            ext = "mkv";
            [fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / AAC Audio" )];
				[fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / AC-3 Audio" )];
			[fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / MP3 Audio" )];
			[fDstCodecsPopUp addItemWithTitle:
                _( @"MPEG-4 Video / Vorbis Audio" )];
            
			[fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / AAC Audio" )];
			[fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / AC-3 Audio" )];
			[fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / MP3 Audio" )];
			[fDstCodecsPopUp addItemWithTitle:
                _( @"AVC/H.264 Video / Vorbis Audio" )];
            /* We disable the create chapters checkbox here since we are NOT .mp4 
			and make sure it is unchecked*/
			[fCreateChapterMarkers setEnabled: YES];
			break;
    }
    [self CodecsPopUpChanged: NULL];

    /* Add/replace to the correct extension */
    if( [string characterAtIndex: [string length] - 4] == '.' )
    {
        [fDstFile2Field setStringValue: [NSString stringWithFormat:
            @"%@.%s", [string substringToIndex: [string length] - 4],
            ext]];
    }
    else
    {
        [fDstFile2Field setStringValue: [NSString stringWithFormat:
            @"%@.%s", string, ext]];
    }

	/* changing the format may mean that we can / can't offer mono or 6ch, */
	/* so call AudioTrackPopUpChanged for both audio tracks to update the mixdown popups */
	[self AudioTrackPopUpChanged: fAudLang1PopUp];
	[self AudioTrackPopUpChanged: fAudLang2PopUp];
	/* We call the method to properly enable/disable turbo 2 pass */
	[self TwoPassCheckboxChanged: sender];
	/* We call method method to change UI to reflect whether a preset is used or not*/
	[self CustomSettingUsed: sender];	
	
}

- (IBAction) CodecsPopUpChanged: (id) sender
{
    int format = [fDstFormatPopUp indexOfSelectedItem];
    int codecs = [fDstCodecsPopUp indexOfSelectedItem];
	[fX264optView setHidden: YES];
	[fX264optViewTitleLabel setStringValue: @"Only Used With The x264 (H.264) Codec"];


    /* Update the encoder popup*/
    if( ( FormatSettings[format][codecs] & HB_VCODEC_X264 ) )
    {
        /* MPEG-4 -> H.264 */
        [fVidEncoderPopUp removeAllItems];
		[fVidEncoderPopUp addItemWithTitle: @"x264 (h.264 Main)"];
		[fVidEncoderPopUp addItemWithTitle: @"x264 (h.264 iPod)"];
		[fVidEncoderPopUp selectItemAtIndex: 0];
        [fX264optView setHidden: NO];
		[fX264optViewTitleLabel setStringValue: @""];


		
    }
    else if( ( FormatSettings[format][codecs] & HB_VCODEC_FFMPEG ) )
    {
        /* H.264 -> MPEG-4 */
        [fVidEncoderPopUp removeAllItems];
        [fVidEncoderPopUp addItemWithTitle: @"FFmpeg"];
        [fVidEncoderPopUp addItemWithTitle: @"XviD"];
        [fVidEncoderPopUp selectItemAtIndex: 0];
				
    }

    if( FormatSettings[format][codecs] & HB_ACODEC_AC3 )
    {
        /* AC-3 pass-through: disable samplerate and bitrate */
        [fAudRatePopUp    setEnabled: NO];
        [fAudBitratePopUp setEnabled: NO];
    }
    else
    {
        [fAudRatePopUp    setEnabled: YES];
        [fAudBitratePopUp setEnabled: YES];
    }
    /* changing the codecs on offer may mean that we can / can't offer mono or 6ch, */
	/* so call AudioTrackPopUpChanged for both audio tracks to update the mixdown popups */
	[self AudioTrackPopUpChanged: fAudLang1PopUp];
	[self AudioTrackPopUpChanged: fAudLang2PopUp];

    [self CalculateBitrate: sender];
    [self TwoPassCheckboxChanged: sender];
}

- (IBAction) EncoderPopUpChanged: (id) sender
{
    
	/* Check to see if we need to modify the job pic values based on x264 (iPod) encoder selection */
    if ([fDstFormatPopUp indexOfSelectedItem] == 0 && [fDstCodecsPopUp indexOfSelectedItem] == 1 && [fVidEncoderPopUp indexOfSelectedItem] == 1)
    {
		hb_job_t * job = fTitle->job;
		job->pixel_ratio = 0 ;
		
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DefaultPicSizeAutoiPod"] > 0)
		{
			
			if (job->width > 640)
			{
				job->width = 640;
			}
			job->keep_ratio = 1;
			hb_fix_aspect( job, HB_KEEP_WIDTH );
			
		}
		/* Make sure the 64bit formatting checkbox is off */
		[fDstMpgLargeFileCheck setState: NSOffState];
	}
    
	[self CalculatePictureSizing: sender];
	[self TwoPassCheckboxChanged: sender];
}

- (IBAction) TwoPassCheckboxChanged: (id) sender
{
	/* check to see if x264 is chosen */
	int format = [fDstFormatPopUp indexOfSelectedItem];
    int codecs = [fDstCodecsPopUp indexOfSelectedItem];
	if( ( FormatSettings[format][codecs] & HB_VCODEC_X264 ) )
    {
		if( [fVidTwoPassCheck state] == NSOnState)
		{
			[fVidTurboPassCheck setHidden: NO];
		}
		else
		{
			[fVidTurboPassCheck setHidden: YES];
			[fVidTurboPassCheck setState: NSOffState];
		}
		/* Make sure Two Pass is checked if Turbo is checked */
		if( [fVidTurboPassCheck state] == NSOnState)
		{
			[fVidTwoPassCheck setState: NSOnState];
		}
	}
	else
	{
		[fVidTurboPassCheck setHidden: YES];
		[fVidTurboPassCheck setState: NSOffState];
	}
	
	/* We call method method to change UI to reflect whether a preset is used or not*/
	[self CustomSettingUsed: sender];
}

- (IBAction) SetEnabledStateOfAudioMixdownControls: (id) sender
{

    /* enable/disable the mixdown text and popupbutton for audio track 1 */
    [fAudTrack1MixPopUp setEnabled: ([fAudLang1PopUp indexOfSelectedItem] == 0) ? NO : YES];
    [fAudTrack1MixLabel setTextColor: ([fAudLang1PopUp indexOfSelectedItem] == 0) ?
        [NSColor disabledControlTextColor] : [NSColor controlTextColor]];

    /* enable/disable the mixdown text and popupbutton for audio track 2 */
    [fAudTrack2MixPopUp setEnabled: ([fAudLang2PopUp indexOfSelectedItem] == 0) ? NO : YES];
    [fAudTrack2MixLabel setTextColor: ([fAudLang2PopUp indexOfSelectedItem] == 0) ?
        [NSColor disabledControlTextColor] : [NSColor controlTextColor]];

}

- (IBAction) AddAllAudioTracksToPopUp: (id) sender
{

    hb_list_t  * list  = hb_get_titles( fHandle );
    hb_title_t * title = (hb_title_t*)
        hb_list_item( list, [fSrcTitlePopUp indexOfSelectedItem] );

	hb_audio_t * audio;

    [sender removeAllItems];
    [sender addItemWithTitle: _( @"None" )];
    for( int i = 0; i < hb_list_count( title->list_audio ); i++ )
    {
        audio = (hb_audio_t *) hb_list_item( title->list_audio, i );
        [[sender menu] addItemWithTitle:
            [NSString stringWithCString: audio->lang]
            action: NULL keyEquivalent: @""];
    }
    [sender selectItemAtIndex: 0];

}

- (IBAction) SelectAudioTrackInPopUp: (id) sender searchPrefixString: (NSString *) searchPrefixString selectIndexIfNotFound: (int) selectIndexIfNotFound
{

    /* this method can be used to find a language, or a language-and-source-format combination, by passing in the appropriate string */
    /* e.g. to find the first French track, pass in an NSString * of "Francais" */
    /* e.g. to find the first English 5.1 AC3 track, pass in an NSString * of "English (AC3) (5.1 ch)" */
    /* if no matching track is found, then selectIndexIfNotFound is used to choose which track to select instead */
    
	if (searchPrefixString != NULL) 
	{

        for( int i = 0; i < [sender numberOfItems]; i++ )
        {
            /* Try to find the desired search string */
            if ([[[sender itemAtIndex: i] title] hasPrefix:searchPrefixString])
            {
                [sender selectItemAtIndex: i];
                return;
            }
        }
        /* couldn't find the string, so select the requested "search string not found" item */
        /* index of 0 means select the "none" item */
        /* index of 1 means select the first audio track */
        [sender selectItemAtIndex: selectIndexIfNotFound];
	}
    else
    {
        /* if no search string is provided, then select the selectIndexIfNotFound item */
        [sender selectItemAtIndex: selectIndexIfNotFound];
    }

}

- (IBAction) AudioTrackPopUpChanged: (id) sender
{
    /* utility function to call AudioTrackPopUpChanged without passing in a mixdown-to-use */
    [self AudioTrackPopUpChanged: sender mixdownToUse: 0];
}

- (IBAction) AudioTrackPopUpChanged: (id) sender mixdownToUse: (int) mixdownToUse
{

    /* make sure we have a selected title before continuing */
    if (fTitle == NULL) return;

    /* find out if audio track 1 or 2 was changed - this is passed to us in the tag of the sender */
    /* the sender will have been either fAudLang1PopUp (tag = 0) or fAudLang2PopUp (tag = 1) */
    int thisAudio = [sender tag];

    /* get the index of the selected audio */
    int thisAudioIndex = [sender indexOfSelectedItem] - 1;

    /* Handbrake can't currently cope with ripping the same source track twice */
    /* So, if this audio is also selected in the other audio track popup, set that popup's selection to "none" */
    /* get a reference to the two audio track popups */
    NSPopUpButton * thisAudioPopUp  = (thisAudio == 1 ? fAudLang2PopUp : fAudLang1PopUp);
    NSPopUpButton * otherAudioPopUp = (thisAudio == 1 ? fAudLang1PopUp : fAudLang2PopUp);
    /* if the same track is selected in the other audio popup, then select "none" in that popup */
    /* unless, of course, both are selected as "none!" */
    if ([thisAudioPopUp indexOfSelectedItem] != 0 && [thisAudioPopUp indexOfSelectedItem] == [otherAudioPopUp indexOfSelectedItem]) {
        [otherAudioPopUp selectItemAtIndex: 0];
        [self AudioTrackPopUpChanged: otherAudioPopUp];
    }

    /* pointer for the hb_audio_s struct we will use later on */
    hb_audio_t * audio;

    /* find out what the currently-selected output audio codec is */
    int format = [fDstFormatPopUp indexOfSelectedItem];
    int codecs = [fDstCodecsPopUp indexOfSelectedItem];
    int acodec = FormatSettings[format][codecs] & HB_ACODEC_MASK;

    /* pointer to this track's mixdown NSPopUpButton */
    NSTextField   * mixdownTextField;
    NSPopUpButton * mixdownPopUp;

    /* find our mixdown NSTextField and NSPopUpButton */
    if (thisAudio == 0)
    {
        mixdownTextField = fAudTrack1MixLabel;
        mixdownPopUp = fAudTrack1MixPopUp;
    }
    else
    {
        mixdownTextField = fAudTrack2MixLabel;
        mixdownPopUp = fAudTrack2MixPopUp;
    }

    /* delete the previous audio mixdown options */
    [mixdownPopUp removeAllItems];

    /* check if the audio mixdown controls need their enabled state changing */
    [self SetEnabledStateOfAudioMixdownControls: NULL];

    if (thisAudioIndex != -1)
    {

        /* get the audio */
        audio = (hb_audio_t *) hb_list_item( fTitle->list_audio, thisAudioIndex );
        if (audio != NULL)
        {

            /* find out if our selected output audio codec supports mono and / or 6ch */
            /* we also check for an input codec of AC3 or DCA,
               as they are the only libraries able to do the mixdown to mono / conversion to 6-ch */
            /* audioCodecsSupportMono and audioCodecsSupport6Ch are the same for now,
               but this may change in the future, so they are separated for flexibility */
            int audioCodecsSupportMono = ((audio->codec == HB_ACODEC_AC3 ||
                audio->codec == HB_ACODEC_DCA) && acodec == HB_ACODEC_FAAC);
            int audioCodecsSupport6Ch =  ((audio->codec == HB_ACODEC_AC3 ||
                audio->codec == HB_ACODEC_DCA) && acodec == HB_ACODEC_FAAC);

            /* check for AC-3 passthru */
            if (audio->codec == HB_ACODEC_AC3 && acodec == HB_ACODEC_AC3)
            {
                    [[mixdownPopUp menu] addItemWithTitle:
                        [NSString stringWithCString: "AC3 Passthru"]
                        action: NULL keyEquivalent: @""];
            }
            else
            {

                /* add the appropriate audio mixdown menuitems to the popupbutton */
                /* in each case, we set the new menuitem's tag to be the amixdown value for that mixdown,
                   so that we can reference the mixdown later */

                /* keep a track of the min and max mixdowns we used, so we can select the best match later */
                int minMixdownUsed = 0;
                int maxMixdownUsed = 0;
                
                /* get the input channel layout without any lfe channels */
                int layout = audio->input_channel_layout & HB_INPUT_CH_LAYOUT_DISCRETE_NO_LFE_MASK;

                /* do we want to add a mono option? */
                if (audioCodecsSupportMono == 1) {
                    id<NSMenuItem> menuItem = [[mixdownPopUp menu] addItemWithTitle:
                        [NSString stringWithCString: hb_audio_mixdowns[0].human_readable_name]
                        action: NULL keyEquivalent: @""];
                    [menuItem setTag: hb_audio_mixdowns[0].amixdown];
                    if (minMixdownUsed == 0) minMixdownUsed = hb_audio_mixdowns[0].amixdown;
                    maxMixdownUsed = MAX(maxMixdownUsed, hb_audio_mixdowns[0].amixdown);
                }

                /* do we want to add a stereo option? */
                /* offer stereo if we have a mono source and non-mono-supporting codecs, as otherwise we won't have a mixdown at all */
                /* also offer stereo if we have a stereo-or-better source */
                if ((layout == HB_INPUT_CH_LAYOUT_MONO && audioCodecsSupportMono == 0) || layout >= HB_INPUT_CH_LAYOUT_STEREO) {
                    id<NSMenuItem> menuItem = [[mixdownPopUp menu] addItemWithTitle:
                        [NSString stringWithCString: hb_audio_mixdowns[1].human_readable_name]
                        action: NULL keyEquivalent: @""];
                    [menuItem setTag: hb_audio_mixdowns[1].amixdown];
                    if (minMixdownUsed == 0) minMixdownUsed = hb_audio_mixdowns[1].amixdown;
                    maxMixdownUsed = MAX(maxMixdownUsed, hb_audio_mixdowns[1].amixdown);
                }

                /* do we want to add a dolby surround (DPL1) option? */
                if (layout == HB_INPUT_CH_LAYOUT_3F1R || layout == HB_INPUT_CH_LAYOUT_3F2R || layout == HB_INPUT_CH_LAYOUT_DOLBY) {
                    id<NSMenuItem> menuItem = [[mixdownPopUp menu] addItemWithTitle:
                        [NSString stringWithCString: hb_audio_mixdowns[2].human_readable_name]
                        action: NULL keyEquivalent: @""];
                    [menuItem setTag: hb_audio_mixdowns[2].amixdown];
                    if (minMixdownUsed == 0) minMixdownUsed = hb_audio_mixdowns[2].amixdown;
                    maxMixdownUsed = MAX(maxMixdownUsed, hb_audio_mixdowns[2].amixdown);
                }

                /* do we want to add a dolby pro logic 2 (DPL2) option? */
                if (layout == HB_INPUT_CH_LAYOUT_3F2R) {
                    id<NSMenuItem> menuItem = [[mixdownPopUp menu] addItemWithTitle:
                        [NSString stringWithCString: hb_audio_mixdowns[3].human_readable_name]
                        action: NULL keyEquivalent: @""];
                    [menuItem setTag: hb_audio_mixdowns[3].amixdown];
                    if (minMixdownUsed == 0) minMixdownUsed = hb_audio_mixdowns[3].amixdown;
                    maxMixdownUsed = MAX(maxMixdownUsed, hb_audio_mixdowns[3].amixdown);
                }

                /* do we want to add a 6-channel discrete option? */
                if (audioCodecsSupport6Ch == 1 && layout == HB_INPUT_CH_LAYOUT_3F2R && (audio->input_channel_layout & HB_INPUT_CH_LAYOUT_HAS_LFE)) {
                    id<NSMenuItem> menuItem = [[mixdownPopUp menu] addItemWithTitle:
                        [NSString stringWithCString: hb_audio_mixdowns[4].human_readable_name]
                        action: NULL keyEquivalent: @""];
                    [menuItem setTag: hb_audio_mixdowns[4].amixdown];
                    if (minMixdownUsed == 0) minMixdownUsed = hb_audio_mixdowns[4].amixdown;
                    maxMixdownUsed = MAX(maxMixdownUsed, hb_audio_mixdowns[4].amixdown);
                }

                /* auto-select the best mixdown based on our saved mixdown preference */
                
                /* for now, this is hard-coded to a "best" mixdown of HB_AMIXDOWN_DOLBYPLII */
                /* ultimately this should be a prefs option */
                int useMixdown;
                
                /* if we passed in a mixdown to use - in order to load a preset - then try and use it */
                if (mixdownToUse > 0)
                {
                    useMixdown = mixdownToUse;
                }
                else
                {
                    useMixdown = HB_AMIXDOWN_DOLBYPLII;
                }
                
                /* if useMixdown > maxMixdownUsed, then use maxMixdownUsed */
                if (useMixdown > maxMixdownUsed) useMixdown = maxMixdownUsed;

                /* if useMixdown < minMixdownUsed, then use minMixdownUsed */
                if (useMixdown < minMixdownUsed) useMixdown = minMixdownUsed;

                /* select the (possibly-amended) preferred mixdown */
                [mixdownPopUp selectItemWithTag: useMixdown];
				
				/* lets call the AudioTrackMixdownChanged method here to determine appropriate bitrates, etc. */
                [self AudioTrackMixdownChanged: NULL];
            }

        }
        
    }

	/* see if the new audio track choice will change the bitrate we need */
    [self CalculateBitrate: sender];	

}
- (IBAction) AudioTrackMixdownChanged: (id) sender
{

    /* find out what the currently-selected output audio codec is */
    int format = [fDstFormatPopUp indexOfSelectedItem];
    int codecs = [fDstCodecsPopUp indexOfSelectedItem];
    int acodec = FormatSettings[format][codecs] & HB_ACODEC_MASK;
    
    /* storage variable for the min and max bitrate allowed for this codec */
    int minbitrate;
    int maxbitrate;
    
    switch( acodec )
    {
        case HB_ACODEC_FAAC:
            /* check if we have a 6ch discrete conversion in either audio track */
            if ([[fAudTrack1MixPopUp selectedItem] tag] == HB_AMIXDOWN_6CH || [[fAudTrack2MixPopUp selectedItem] tag] == HB_AMIXDOWN_6CH)
            {
                /* FAAC is happy using our min bitrate of 32 kbps, even for 6ch */
                minbitrate = 32;
                /* If either mixdown popup includes 6-channel discrete, then allow up to 384 kbps */
                maxbitrate = 384;
                break;
            }
            else
            {
                /* FAAC is happy using our min bitrate of 32 kbps for stereo or mono */
                minbitrate = 32;
                /* FAAC won't honour anything more than 160 for stereo, so let's not offer it */
                /* note: haven't dealt with mono separately here, FAAC will just use the max it can */
                maxbitrate = 160;
                break;
            }

        case HB_ACODEC_LAME:
            /* Lame is happy using our min bitrate of 32 kbps */
            minbitrate = 32;
            /* Lame won't encode if the bitrate is higher than 320 kbps */
            maxbitrate = 320;
            break;

        case HB_ACODEC_VORBIS:
            /* Vorbis causes a crash if we use a bitrate below 48 kbps */
            minbitrate = 48;
            /* Vorbis can cope with 384 kbps quite happily, even for stereo */
            maxbitrate = 384;
            break;

        default:
            /* AC3 passthru disables the bitrate dropdown anyway, so we might as well just use the min and max bitrate */
            minbitrate = 32;
            maxbitrate = 384;
        
    }

    [fAudBitratePopUp removeAllItems];

    for( int i = 0; i < hb_audio_bitrates_count; i++ )
    {
        if (hb_audio_bitrates[i].rate >= minbitrate && hb_audio_bitrates[i].rate <= maxbitrate)
        {
            /* add a new menuitem for this bitrate */
            id<NSMenuItem> menuItem = [[fAudBitratePopUp menu] addItemWithTitle:
                [NSString stringWithCString: hb_audio_bitrates[i].string]
                action: NULL keyEquivalent: @""];
            /* set its tag to be the actual bitrate as an integer, so we can retrieve it later */
            [menuItem setTag: hb_audio_bitrates[i].rate];
        }
    }

    /* select the default bitrate (but use 384 for 6-ch AAC) */
    if ([[fAudTrack1MixPopUp selectedItem] tag] == HB_AMIXDOWN_6CH || [[fAudTrack2MixPopUp selectedItem] tag] == HB_AMIXDOWN_6CH)
    {
        [fAudBitratePopUp selectItemWithTag: 384];
    }
    else
    {
        [fAudBitratePopUp selectItemWithTag: hb_audio_bitrates[hb_audio_bitrates_default].rate];
    }

}
/* lets set the picture size back to the max from right after title scan
   Lets use an IBAction here as down the road we could always use a checkbox
   in the gui to easily take the user back to max. Remember, the compiler
   resolves IBActions down to -(void) during compile anyway */
- (IBAction) RevertPictureSizeToMax: (id) sender
{
	 hb_job_t * job = fTitle->job;
	/* We use the output picture width and height
	as calculated from libhb right after title is set
	in TitlePopUpChanged */
	job->width = PicOrigOutputWidth;
	job->height = PicOrigOutputHeight;


    
	[self CalculatePictureSizing: sender];
	/* We call method method to change UI to reflect whether a preset is used or not*/    
    [self CustomSettingUsed: sender];
}


/* Get and Display Current Pic Settings in main window */
- (IBAction) CalculatePictureSizing: (id) sender
{
	

	[fPicSettingWidth setStringValue: [NSString stringWithFormat:
		@"%d", fTitle->job->width]];
	[fPicSettingHeight setStringValue: [NSString stringWithFormat:
		@"%d", fTitle->job->height]];
	[fPicSettingARkeep setStringValue: [NSString stringWithFormat:
		@"%d", fTitle->job->keep_ratio]];		 
	[fPicSettingDeinterlace setStringValue: [NSString stringWithFormat:
		@"%d", fTitle->job->deinterlace]];
	[fPicSettingPAR setStringValue: [NSString stringWithFormat:
		@"%d", fTitle->job->pixel_ratio]];
		
	if (fTitle->job->pixel_ratio == 1)
	{
	int titlewidth = fTitle->width-fTitle->job->crop[2]-fTitle->job->crop[3];
	int arpwidth = fTitle->job->pixel_aspect_width;
	int arpheight = fTitle->job->pixel_aspect_height;
	int displayparwidth = titlewidth * arpwidth / arpheight;
	int displayparheight = fTitle->height-fTitle->job->crop[0]-fTitle->job->crop[1];
	[fPicSettingWidth setStringValue: [NSString stringWithFormat:
		@"%d", titlewidth]];
	[fPicSettingHeight setStringValue: [NSString stringWithFormat:
		@"%d", displayparheight]];
	[fPicLabelPAROutp setStringValue: @"Anamorphic Output:"];
	[fPicLabelPAROutputX setStringValue: @"x"];
    [fPicSettingPARWidth setStringValue: [NSString stringWithFormat:
        @"%d", displayparwidth]];
	[fPicSettingPARHeight setStringValue: [NSString stringWithFormat:
        @"%d", displayparheight]];

	fTitle->job->keep_ratio = 0;
	}
	else
	{
	[fPicLabelPAROutp setStringValue: @""];
	[fPicLabelPAROutputX setStringValue: @""];
	[fPicSettingPARWidth setStringValue: @""];
	[fPicSettingPARHeight setStringValue:  @""];
	}
		
	/* Set ON/Off values for the deinterlace/keep aspect ratio according to boolean */	
	if (fTitle->job->keep_ratio > 0)
	{
		[fPicSettingARkeepDsply setStringValue: @"On"];
	}
	else
	{
		[fPicSettingARkeepDsply setStringValue: @"Off"];
	}	
	if (fTitle->job->deinterlace > 0)
	{
		[fPicSettingDeinterlaceDsply setStringValue: @"On"];
	}
	else
	{
		[fPicSettingDeinterlaceDsply setStringValue: @"Off"];
	}
	if (fTitle->job->pixel_ratio > 0)
	{
		[fPicSettingPARDsply setStringValue: @"On"];
	}
	else
	{
		[fPicSettingPARDsply setStringValue: @"Off"];
	}
	/* Set the display field for crop as per boolean */
	if ([[fPicSettingAutoCrop stringValue] isEqualToString: @"0"])
	{
	    [fPicSettingAutoCropDsply setStringValue: @"Custom"];
	}
	else
	{
		[fPicSettingAutoCropDsply setStringValue: @"Auto"];
	}	
	
	/* below will trigger the preset, if selected, to be
	changed to "Custom". Lets comment out for now until
	we figure out a way to determine if the picture values
	changed modify the preset values */	
	//[self CustomSettingUsed: sender];
}

- (IBAction) CalculateBitrate: (id) sender
{
    if( !fHandle || [fVidQualityMatrix selectedRow] != 0 )
    {
        return;
    }

    hb_list_t  * list  = hb_get_titles( fHandle );
    hb_title_t * title = (hb_title_t *) hb_list_item( list,
            [fSrcTitlePopUp indexOfSelectedItem] );
    hb_job_t * job = title->job;

    [self PrepareJob];

    [fVidBitrateField setIntValue: hb_calc_bitrate( job,
            [fVidTargetSizeField intValue] )];
			
			
}

/* Method to determine if we should change the UI
To reflect whether or not a Preset is being used or if
the user is using "Custom" settings by determining the sender*/
- (IBAction) CustomSettingUsed: (id) sender
{
	if ([sender stringValue] != NULL)
	{
		/* Deselect the currently selected Preset if there is one*/
		[tableView deselectRow:[tableView selectedRow]];
		/* Change UI to show "Custom" settings are being used */
		[fPresetSelectedDisplay setStringValue: @"Custom"];
		
		curUserPresetChosenNum = nil;

		
	}

}

- (IBAction) X264AdvancedOptionsSet: (id) sender
{
    /*Set opt widget values here*/
    
    /*B-Frames fX264optBframesPopUp*/
    int i;
    [fX264optBframesPopUp removeAllItems];
    [fX264optBframesPopUp addItemWithTitle:@"Default (0)"];
    for (i=0; i<17;i++)
    {
        [fX264optBframesPopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }
    
    /*Reference Frames fX264optRefPopUp*/
    [fX264optRefPopUp removeAllItems];
    [fX264optRefPopUp addItemWithTitle:@"Default (1)"];
    for (i=0; i<17;i++)
    {
        [fX264optRefPopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }
    
    /*No Fast P-Skip fX264optNfpskipSwitch BOOLEAN*/
    [fX264optNfpskipSwitch setState:0];
    
    /*No Dict Decimate fX264optNodctdcmtSwitch BOOLEAN*/
    [fX264optNodctdcmtSwitch setState:0];    

    /*Sub Me fX264optSubmePopUp*/
    [fX264optSubmePopUp removeAllItems];
    [fX264optSubmePopUp addItemWithTitle:@"Default (4)"];
    for (i=0; i<8;i++)
    {
        [fX264optSubmePopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }
    
    /*Trellis fX264optTrellisPopUp*/
    [fX264optTrellisPopUp removeAllItems];
    [fX264optTrellisPopUp addItemWithTitle:@"Default (0)"];
    for (i=0; i<3;i++)
    {
        [fX264optTrellisPopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }
    
    /*Mixed-references fX264optMixedRefsSwitch BOOLEAN*/
    [fX264optMixedRefsSwitch setState:0];
    
    /*Motion Estimation fX264optMotionEstPopUp*/
    [fX264optMotionEstPopUp removeAllItems];
    [fX264optMotionEstPopUp addItemWithTitle:@"Default (Hexagon)"];
    [fX264optMotionEstPopUp addItemWithTitle:@"Diamond"];
    [fX264optMotionEstPopUp addItemWithTitle:@"Hexagon"];
    [fX264optMotionEstPopUp addItemWithTitle:@"Uneven Multi-Hexagon"];
    [fX264optMotionEstPopUp addItemWithTitle:@"Exhaustive"];
    
    /*Motion Estimation range fX264optMERangePopUp*/
    [fX264optMERangePopUp removeAllItems];
    [fX264optMERangePopUp addItemWithTitle:@"Default (16)"];
    for (i=4; i<65;i++)
    {
        [fX264optMERangePopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }
    
    /*Weighted B-Frame Prediction fX264optWeightBSwitch BOOLEAN*/
    [fX264optWeightBSwitch setState:0];
    
    /*B-Frame Rate Distortion Optimization fX264optBRDOSwitch BOOLEAN*/
    [fX264optBRDOSwitch setState:0];
    
    /*B-frame Pyramids fX264optBPyramidSwitch BOOLEAN*/
    [fX264optBPyramidSwitch setState:0];
    
    /*Bidirectional Motion Estimation Refinement fX264optBiMESwitch BOOLEAN*/
    [fX264optBiMESwitch setState:0];
    
    /*Direct B-Frame Prediction Mode fX264optDirectPredPopUp*/
    [fX264optDirectPredPopUp removeAllItems];
    [fX264optDirectPredPopUp addItemWithTitle:@"Default (Spatial)"];
    [fX264optDirectPredPopUp addItemWithTitle:@"None"];
    [fX264optDirectPredPopUp addItemWithTitle:@"Spatial"];
    [fX264optDirectPredPopUp addItemWithTitle:@"Temporal"];
    [fX264optDirectPredPopUp addItemWithTitle:@"Automatic"];
    
    /*Alpha Deblock*/
    [fX264optAlphaDeblockPopUp removeAllItems];
    [fX264optAlphaDeblockPopUp addItemWithTitle:@"Default (0)"];
    for (i=-6; i<7;i++)
    {
        [fX264optAlphaDeblockPopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }
    
    /*Beta Deblock*/
    [fX264optBetaDeblockPopUp removeAllItems];
    [fX264optBetaDeblockPopUp addItemWithTitle:@"Default (0)"];
    for (i=-6; i<7;i++)
    {
        [fX264optBetaDeblockPopUp addItemWithTitle:[NSString stringWithFormat:@"%d",i]];
    }     
    
    /* Analysis fX264optAnalysePopUp */
    [fX264optAnalysePopUp removeAllItems];
    [fX264optAnalysePopUp addItemWithTitle:@"Default (some)"]; /* 0=default */
    [fX264optAnalysePopUp addItemWithTitle:[NSString stringWithFormat:@"None"]]; /* 1=none */
    [fX264optAnalysePopUp addItemWithTitle:[NSString stringWithFormat:@"All"]]; /* 2=all */
    
    /* 8x8 DCT fX264op8x8dctSwitch */
    [fX264opt8x8dctSwitch setState:0];
    
    /* CABAC fX264opCabacSwitch */
    [fX264optCabacSwitch setState:1];

    /* Standardize the option string */
    [self X264AdvancedOptionsStandardizeOptString: NULL];
    /* Set Current GUI Settings based on newly standardized string */
    [self X264AdvancedOptionsSetCurrentSettings: NULL];
}

- (IBAction) X264AdvancedOptionsStandardizeOptString: (id) sender
{
    /* Set widgets depending on the opt string in field */
    NSString * thisOpt; // The separated option such as "bframes=3"
    NSString * optName = @""; // The option name such as "bframes"
    NSString * optValue = @"";// The option value such as "3"
    NSString * changedOptString = @"";
    NSArray *currentOptsArray;

    /*First, we get an opt string to process */
    NSString *currentOptString = [fDisplayX264Options stringValue];

    /*verify there is an opt string to process */
    NSRange currentOptRange = [currentOptString rangeOfString:@"="];
    if (currentOptRange.location != NSNotFound)
    {
        /*Put individual options into an array based on the ":" separator for processing, result is "<opt>=<value>"*/
        currentOptsArray = [currentOptString componentsSeparatedByString:@":"];

        /*iterate through the array and get <opts> and <values*/
        //NSEnumerator * enumerator = [currentOptsArray objectEnumerator];
        int loopcounter;
        int currentOptsArrayCount = [currentOptsArray count];
        for (loopcounter = 0; loopcounter < currentOptsArrayCount; loopcounter++)
        {
            thisOpt = [currentOptsArray objectAtIndex:loopcounter];
            
            NSRange splitOptRange = [thisOpt rangeOfString:@"="];
            if (splitOptRange.location != NSNotFound)
            {
                optName = [thisOpt substringToIndex:splitOptRange.location];
                optValue = [thisOpt substringFromIndex:splitOptRange.location + 1];
                
                /* Standardize the names here depending on whats in the string */
                optName = [self X264AdvancedOptionsStandardizeOptNames:optName];
                thisOpt = [NSString stringWithFormat:@"%@=%@",optName,optValue];	
            }
            else // No value given so we use a default of "1"
            {
                optName = thisOpt;
                /* Standardize the names here depending on whats in the string */
                optName = [self X264AdvancedOptionsStandardizeOptNames:optName];
                thisOpt = [NSString stringWithFormat:@"%@=%d",optName,1];
            }
            
            /* Construct New String for opts here */
            if ([thisOpt isEqualToString:@""])
            {
                changedOptString = [NSString stringWithFormat:@"%@%@",changedOptString,thisOpt];
            }
            else
            {
                if ([changedOptString isEqualToString:@""])
                {
                    changedOptString = [NSString stringWithFormat:@"%@",thisOpt];
                }
                else
                {
                    changedOptString = [NSString stringWithFormat:@"%@:%@",changedOptString,thisOpt];
                }
            }
        }
    }
    
    /* Change the option string to reflect the new standardized option string */
    [fDisplayX264Options setStringValue:[NSString stringWithFormat:changedOptString]];
}

- (NSString *) X264AdvancedOptionsStandardizeOptNames:(NSString *) cleanOptNameString
{
    if ([cleanOptNameString isEqualToString:@"ref"] || [cleanOptNameString isEqualToString:@"frameref"])
    {
        cleanOptNameString = @"ref";
    }
    
    /*No Fast PSkip nofast_pskip*/
    if ([cleanOptNameString isEqualToString:@"no-fast-pskip"] || [cleanOptNameString isEqualToString:@"no_fast_pskip"] || [cleanOptNameString isEqualToString:@"nofast_pskip"])
    {
        cleanOptNameString = @"no-fast-pskip";
    }
    
    /*No Dict Decimate*/
    if ([cleanOptNameString isEqualToString:@"no-dct-decimate"] || [cleanOptNameString isEqualToString:@"no_dct_decimate"] || [cleanOptNameString isEqualToString:@"nodct_decimate"])
    {
        cleanOptNameString = @"no-dct-decimate";
    }
    
    /*Subme*/
    if ([cleanOptNameString isEqualToString:@"subme"])
    {
        cleanOptNameString = @"subq";
    }
    
    /*ME Range*/
    if ([cleanOptNameString isEqualToString:@"me-range"] || [cleanOptNameString isEqualToString:@"me_range"])
        cleanOptNameString = @"merange";
    
    /*WeightB*/
    if ([cleanOptNameString isEqualToString:@"weight-b"] || [cleanOptNameString isEqualToString:@"weight_b"])
    {
        cleanOptNameString = @"weightb";
    }
    
    /*BRDO*/
    if ([cleanOptNameString isEqualToString:@"b-rdo"] || [cleanOptNameString isEqualToString:@"b_rdo"])
    {
        cleanOptNameString = @"brdo";
    }
    
    /*B Pyramid*/
    if ([cleanOptNameString isEqualToString:@"b_pyramid"])
    {
        cleanOptNameString = @"b-pyramid";
    }
    
    /*Direct Prediction*/
    if ([cleanOptNameString isEqualToString:@"direct-pred"] || [cleanOptNameString isEqualToString:@"direct_pred"])
    {
        cleanOptNameString = @"direct";
    }
    
    /*Deblocking*/
    if ([cleanOptNameString isEqualToString:@"filter"])
    {
        cleanOptNameString = @"deblock";
    }

    /*Analysis*/
    if ([cleanOptNameString isEqualToString:@"partitions"])
    {
        cleanOptNameString = @"analyse";
    }

        
    return cleanOptNameString;	
}

- (IBAction) X264AdvancedOptionsSetCurrentSettings: (id) sender
{
    /* Set widgets depending on the opt string in field */
    NSString * thisOpt; // The separated option such as "bframes=3"
    NSString * optName = @""; // The option name such as "bframes"
    NSString * optValue = @"";// The option value such as "3"
    NSArray *currentOptsArray;
    
    /*First, we get an opt string to process */
    //NSString *currentOptString = @"bframes=3:ref=1:subme=5:me=umh:no-fast-pskip=1:no-dct-decimate=1:trellis=2";
    NSString *currentOptString = [fDisplayX264Options stringValue];
    
    /*verify there is an opt string to process */
    NSRange currentOptRange = [currentOptString rangeOfString:@"="];
    if (currentOptRange.location != NSNotFound)
    {
        /* lets clean the opt string here to standardize any names*/
        /*Put individual options into an array based on the ":" separator for processing, result is "<opt>=<value>"*/
        currentOptsArray = [currentOptString componentsSeparatedByString:@":"];
        
        /*iterate through the array and get <opts> and <values*/
        //NSEnumerator * enumerator = [currentOptsArray objectEnumerator];
        int loopcounter;
        int currentOptsArrayCount = [currentOptsArray count];
        
        /*iterate through the array and get <opts> and <values*/
        for (loopcounter = 0; loopcounter < currentOptsArrayCount; loopcounter++)
        {
            thisOpt = [currentOptsArray objectAtIndex:loopcounter];
            NSRange splitOptRange = [thisOpt rangeOfString:@"="];
            
            if (splitOptRange.location != NSNotFound)
            {
                optName = [thisOpt substringToIndex:splitOptRange.location];
                optValue = [thisOpt substringFromIndex:splitOptRange.location + 1];
           
                /*Run through the available widgets for x264 opts and set them, as you add widgets, 
                they need to be added here. This should be moved to its own method probably*/
           
                /*bframes NSPopUpButton*/
                if ([optName isEqualToString:@"bframes"])
                {
                    [fX264optBframesPopUp selectItemAtIndex:[optValue intValue]+1];
                }
                /*ref NSPopUpButton*/
                if ([optName isEqualToString:@"ref"])
                {
                   [fX264optRefPopUp selectItemAtIndex:[optValue intValue]+1];
                }
                /*No Fast PSkip NSPopUpButton*/
                if ([optName isEqualToString:@"no-fast-pskip"])
                {
                    [fX264optNfpskipSwitch setState:[optValue intValue]];
                }
                /*No Dict Decimate NSPopUpButton*/
                if ([optName isEqualToString:@"no-dct-decimate"])
                {
                    [fX264optNodctdcmtSwitch setState:[optValue intValue]];
                }
                /*Sub Me NSPopUpButton*/
                if ([optName isEqualToString:@"subq"])
                {
                    [fX264optSubmePopUp selectItemAtIndex:[optValue intValue]+1];
                }
                /*Trellis NSPopUpButton*/
                if ([optName isEqualToString:@"trellis"])
                {
                    [fX264optTrellisPopUp selectItemAtIndex:[optValue intValue]+1];
                }
                /*Mixed Refs NSButton*/
                if ([optName isEqualToString:@"mixed-refs"])
                {
                    [fX264optMixedRefsSwitch setState:[optValue intValue]];
                }
                /*Motion Estimation NSPopUpButton*/
                if ([optName isEqualToString:@"me"])
                {
                    if ([optValue isEqualToString:@"dia"])
                        [fX264optMotionEstPopUp selectItemAtIndex:1];
                    else if ([optValue isEqualToString:@"hex"])
                        [fX264optMotionEstPopUp selectItemAtIndex:2];
                    else if ([optValue isEqualToString:@"umh"])
                        [fX264optMotionEstPopUp selectItemAtIndex:3];
                    else if ([optValue isEqualToString:@"esa"])
                        [fX264optMotionEstPopUp selectItemAtIndex:4];                        
                }
                /*ME Range NSPopUpButton*/
                if ([optName isEqualToString:@"merange"])
                {
                    [fX264optMERangePopUp selectItemAtIndex:[optValue intValue]-3];
                }
                /*Weighted B-Frames NSPopUpButton*/
                if ([optName isEqualToString:@"weightb"])
                {
                    [fX264optWeightBSwitch setState:[optValue intValue]];
                }
                /*BRDO NSPopUpButton*/
                if ([optName isEqualToString:@"brdo"])
                {
                    [fX264optBRDOSwitch setState:[optValue intValue]];
                }
                /*B Pyramid NSPopUpButton*/
                if ([optName isEqualToString:@"b-pyramid"])
                {
                    [fX264optBPyramidSwitch setState:[optValue intValue]];
                }
                /*Bidirectional Motion Estimation Refinement NSPopUpButton*/
                if ([optName isEqualToString:@"bime"])
                {
                    [fX264optBiMESwitch setState:[optValue intValue]];
                }
                /*Direct B-frame Prediction NSPopUpButton*/
                if ([optName isEqualToString:@"direct"])
                {
                    if ([optValue isEqualToString:@"none"])
                        [fX264optDirectPredPopUp selectItemAtIndex:1];
                    else if ([optValue isEqualToString:@"spatial"])
                        [fX264optDirectPredPopUp selectItemAtIndex:2];
                    else if ([optValue isEqualToString:@"temporal"])
                        [fX264optDirectPredPopUp selectItemAtIndex:3];
                    else if ([optValue isEqualToString:@"auto"])
                        [fX264optDirectPredPopUp selectItemAtIndex:4];                        
                }
                /*Deblocking NSPopUpButtons*/
                if ([optName isEqualToString:@"deblock"])
                {
                    NSString * alphaDeblock = @"";
                    NSString * betaDeblock = @"";
                
                    NSRange splitDeblock = [optValue rangeOfString:@","];
                    alphaDeblock = [optValue substringToIndex:splitDeblock.location];
                    betaDeblock = [optValue substringFromIndex:splitDeblock.location + 1];
                    
                    if ([alphaDeblock isEqualToString:@"0"] && [betaDeblock isEqualToString:@"0"])
                    {
                        [fX264optAlphaDeblockPopUp selectItemAtIndex:0];                        
                        [fX264optBetaDeblockPopUp selectItemAtIndex:0];                               
                    }
                    else
                    {
                        if (![alphaDeblock isEqualToString:@"0"])
                        {
                            [fX264optAlphaDeblockPopUp selectItemAtIndex:[alphaDeblock intValue]+7];
                        }
                        else
                        {
                            [fX264optAlphaDeblockPopUp selectItemAtIndex:7];                        
                        }
                        
                        if (![betaDeblock isEqualToString:@"0"])
                        {
                            [fX264optBetaDeblockPopUp selectItemAtIndex:[betaDeblock intValue]+7];
                        }
                        else
                        {
                            [fX264optBetaDeblockPopUp selectItemAtIndex:7];                        
                        }
                    }
                }
                /* Analysis NSPopUpButton */
                if ([optName isEqualToString:@"analyse"])
                {
                    if ([optValue isEqualToString:@"p8x8,b8x8,i8x8,i4x4"])
                    {
                        [fX264optAnalysePopUp selectItemAtIndex:0];
                    }
                    if ([optValue isEqualToString:@"none"])
                    {
                        [fX264optAnalysePopUp selectItemAtIndex:1];
                    }
                    if ([optValue isEqualToString:@"all"])
                    {
                        [fX264optAnalysePopUp selectItemAtIndex:2];
                    }
                }
                /* 8x8 DCT NSButton */
                if ([optName isEqualToString:@"8x8dct"])
                {
                    [fX264opt8x8dctSwitch setState:[optValue intValue]];
                }
                /* CABAC NSButton */
                if ([optName isEqualToString:@"cabac"])
                {
                    [fX264optCabacSwitch setState:[optValue intValue]];
                }                                                                 
            }
        }
    }
}

- (IBAction) X264AdvancedOptionsChanged: (id) sender
{
    /*Determine which outlet is being used and set optName to process accordingly */
    NSString * optNameToChange = @""; // The option name such as "bframes"

    if (sender == fX264optBframesPopUp)
    {
        optNameToChange = @"bframes";
    }
    if (sender == fX264optRefPopUp)
    {
        optNameToChange = @"ref";
    }
    if (sender == fX264optNfpskipSwitch)
    {
        optNameToChange = @"no-fast-pskip";
    }
    if (sender == fX264optNodctdcmtSwitch)
    {
        optNameToChange = @"no-dct-decimate";
    }
    if (sender == fX264optSubmePopUp)
    {
        optNameToChange = @"subq";
    }
    if (sender == fX264optTrellisPopUp)
    {
        optNameToChange = @"trellis";
    }
    if (sender == fX264optMixedRefsSwitch)
    {
        optNameToChange = @"mixed-refs";
    }
    if (sender == fX264optMotionEstPopUp)
    {
        optNameToChange = @"me";
    }
    if (sender == fX264optMERangePopUp)
    {
        optNameToChange = @"merange";
    }
    if (sender == fX264optWeightBSwitch)
    {
        optNameToChange = @"weightb";
    }
    if (sender == fX264optBRDOSwitch)
    {
        optNameToChange = @"brdo";
    }
    if (sender == fX264optBPyramidSwitch)
    {
        optNameToChange = @"b-pyramid";
    }
    if (sender == fX264optBiMESwitch)
    {
        optNameToChange = @"bime";
    }
    if (sender == fX264optDirectPredPopUp)
    {
        optNameToChange = @"direct";
    }
    if (sender == fX264optAlphaDeblockPopUp)
    {
        optNameToChange = @"deblock";
    }
    if (sender == fX264optBetaDeblockPopUp)
    {
        optNameToChange = @"deblock";
    }        
    if (sender == fX264optAnalysePopUp)
    {
        optNameToChange = @"analyse";
    }
    if (sender == fX264opt8x8dctSwitch)
    {
        optNameToChange = @"8x8dct";
    }
    if (sender == fX264optCabacSwitch)
    {
        optNameToChange = @"cabac";
    }
    
    /* Set widgets depending on the opt string in field */
    NSString * thisOpt; // The separated option such as "bframes=3"
    NSString * optName = @""; // The option name such as "bframes"
    NSString * optValue = @"";// The option value such as "3"
    NSArray *currentOptsArray;

    /*First, we get an opt string to process */
    //EXAMPLE: NSString *currentOptString = @"bframes=3:ref=1:subme=5:me=umh:no-fast-pskip=1:no-dct-decimate=1:trellis=2";
    NSString *currentOptString = [fDisplayX264Options stringValue];

    /*verify there is an occurrence of the opt specified by the sender to change */
    /*take care of any multi-value opt names here. This is extremely kludgy, but test for functionality
    and worry about pretty later */
	
	/*First, we create a pattern to check for ":"optNameToChange"=" to modify the option if the name falls after
	the first character of the opt string (hence the ":") */
	NSString *checkOptNameToChange = [NSString stringWithFormat:@":%@=",optNameToChange];
    NSRange currentOptRange = [currentOptString rangeOfString:checkOptNameToChange];
	/*Then we create a pattern to check for "<beginning of line>"optNameToChange"=" to modify the option to
	see if the name falls at the beginning of the line, where we would not have the ":" as a pattern to test against*/
	NSString *checkOptNameToChangeBeginning = [NSString stringWithFormat:@"%@=",optNameToChange];
    NSRange currentOptRangeBeginning = [currentOptString rangeOfString:checkOptNameToChangeBeginning];
    if (currentOptRange.location != NSNotFound || currentOptRangeBeginning.location == 0)
    {
        /* Create new empty opt string*/
        NSString *changedOptString = @"";

        /*Put individual options into an array based on the ":" separator for processing, result is "<opt>=<value>"*/
        currentOptsArray = [currentOptString componentsSeparatedByString:@":"];

        /*iterate through the array and get <opts> and <values*/
        int loopcounter;
        int currentOptsArrayCount = [currentOptsArray count];
        for (loopcounter = 0; loopcounter < currentOptsArrayCount; loopcounter++)
        {
            thisOpt = [currentOptsArray objectAtIndex:loopcounter];
            NSRange splitOptRange = [thisOpt rangeOfString:@"="];

            if (splitOptRange.location != NSNotFound)
            {
                optName = [thisOpt substringToIndex:splitOptRange.location];
                optValue = [thisOpt substringFromIndex:splitOptRange.location + 1];
                
                /*Run through the available widgets for x264 opts and set them, as you add widgets, 
                they need to be added here. This should be moved to its own method probably*/
                
                /*If the optNameToChange is found, appropriately change the value or delete it if
                "Unspecified" is set.*/
                if ([optName isEqualToString:optNameToChange])
                {
                    if ([optNameToChange isEqualToString:@"deblock"])
                    {
                        if ((([fX264optAlphaDeblockPopUp indexOfSelectedItem] == 0) || ([fX264optAlphaDeblockPopUp indexOfSelectedItem] == 7)) && (([fX264optBetaDeblockPopUp indexOfSelectedItem] == 0) || ([fX264optBetaDeblockPopUp indexOfSelectedItem] == 7)))
                        {
                            thisOpt = @"";                                
                        }
                        else
                        {
                            thisOpt = [NSString stringWithFormat:@"%@=%d,%d",optName, ([fX264optAlphaDeblockPopUp indexOfSelectedItem] != 0) ? [fX264optAlphaDeblockPopUp indexOfSelectedItem]-7 : 0,([fX264optBetaDeblockPopUp indexOfSelectedItem] != 0) ? [fX264optBetaDeblockPopUp indexOfSelectedItem]-7 : 0];
                        }
                    }
                    else if /*Boolean Switches*/ ([optNameToChange isEqualToString:@"mixed-refs"] || [optNameToChange isEqualToString:@"weightb"] || [optNameToChange isEqualToString:@"brdo"] || [optNameToChange isEqualToString:@"bime"] || [optNameToChange isEqualToString:@"b-pyramid"] || [optNameToChange isEqualToString:@"no-fast-pskip"] || [optNameToChange isEqualToString:@"no-dct-decimate"] || [optNameToChange isEqualToString:@"8x8dct"] )
                    {
                        if ([sender state] == 0)
                        {
                            thisOpt = @"";
                        }
                        else
                        {
                            thisOpt = [NSString stringWithFormat:@"%@=%d",optName,1];
                        }
                    }
                    else if ([optNameToChange isEqualToString:@"cabac"])
                    {
                        if ([sender state] == 1)
                        {
                            thisOpt = @"";
                        }
                        else
                        {
                            thisOpt = [NSString stringWithFormat:@"%@=%d",optName,0];
                        }
                    }                                        
                    else if (([sender indexOfSelectedItem] == 0) && (sender != fX264optAlphaDeblockPopUp) && (sender != fX264optBetaDeblockPopUp) ) // means that "unspecified" is chosen, lets then remove it from the string
                    {
                        thisOpt = @"";
                    }
                    else if ([optNameToChange isEqualToString:@"me"])
                    {
                        switch ([sender indexOfSelectedItem])
                        {   
                            case 1:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"dia"];
                               break;
 
                            case 2:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"hex"];
                               break;
 
                            case 3:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"umh"];
                               break;
 
                            case 4:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"esa"];
                               break;
                            
                            default:
                                break;
                        }
                    }
                    else if ([optNameToChange isEqualToString:@"direct"])
                    {
                        switch ([sender indexOfSelectedItem])
                        {   
                            case 1:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"none"];
                               break;
 
                            case 2:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"spatial"];
                               break;
 
                            case 3:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"temporal"];
                               break;
 
                            case 4:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"auto"];
                               break;
                            
                            default:
                                break;
                        }
                    }
                    else if ([optNameToChange isEqualToString:@"analyse"])
                    {
                        switch ([sender indexOfSelectedItem])
                        {   
                            case 1:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"none"];
                               break;
 
                            case 2:
                               thisOpt = [NSString stringWithFormat:@"%@=%@",optName,@"all"];
                               break;
                            
                            default:
                                break;
                        }
                    }
                    else if ([optNameToChange isEqualToString:@"merange"])
                    {
                        thisOpt = [NSString stringWithFormat:@"%@=%d",optName,[sender indexOfSelectedItem]+3];
                    }
                    else // we have a valid value to change, so change it
                    {
                        thisOpt = [NSString stringWithFormat:@"%@=%d",optName,[sender indexOfSelectedItem]-1];
                    }
                }
            }

            /* Construct New String for opts here */
            if ([thisOpt isEqualToString:@""])
            {
                changedOptString = [NSString stringWithFormat:@"%@%@",changedOptString,thisOpt];
            }
            else
            {
                if ([changedOptString isEqualToString:@""])
                {
                    changedOptString = [NSString stringWithFormat:@"%@",thisOpt];
                }
                else
                {
                    changedOptString = [NSString stringWithFormat:@"%@:%@",changedOptString,thisOpt];
                }
            }
        }

        /* Change the option string to reflect the new mod settings */
        [fDisplayX264Options setStringValue:[NSString stringWithFormat:changedOptString]];	
    }
    else // if none exists, add it to the string
    {
        if ([[fDisplayX264Options stringValue] isEqualToString: @""])
        {
            if ([optNameToChange isEqualToString:@"me"])
            {
                switch ([sender indexOfSelectedItem])
                {   
                    case 1:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"dia"]]];
                        break;
               
                    case 2:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"hex"]]];
                        break;
               
                   case 3:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"umh"]]];
                        break;
               
                   case 4:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"esa"]]];
                        break;
                   
                   default:
                        break;
                }
            }
            else if ([optNameToChange isEqualToString:@"direct"])
            {
                switch ([sender indexOfSelectedItem])
                {   
                    case 1:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"none"]]];
                        break;
               
                    case 2:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"spatial"]]];
                        break;
               
                   case 3:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"temporal"]]];
                        break;
               
                   case 4:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"auto"]]];
                        break;
                   
                   default:
                        break;
                }
            }
            else if ([optNameToChange isEqualToString:@"analyse"])
            {
                switch ([sender indexOfSelectedItem])
                {   
                    case 1:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"none"]]];
                        break;
               
                    case 2:
                        [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                            [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"all"]]];
                        break;
                   
                   default:
                        break;
                }
            }

            else if ([optNameToChange isEqualToString:@"merange"])
            {
                [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                    [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender indexOfSelectedItem]+3]]];
            }
            else if ([optNameToChange isEqualToString:@"deblock"])
            {
                [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d,%d", ([fX264optAlphaDeblockPopUp indexOfSelectedItem] != 0) ? [fX264optAlphaDeblockPopUp indexOfSelectedItem]-7 : 0, ([fX264optBetaDeblockPopUp indexOfSelectedItem] != 0) ? [fX264optBetaDeblockPopUp indexOfSelectedItem]-7 : 0]]];                
            }
            else if /*Boolean Switches*/ ([optNameToChange isEqualToString:@"mixed-refs"] || [optNameToChange isEqualToString:@"weightb"] || [optNameToChange isEqualToString:@"brdo"] || [optNameToChange isEqualToString:@"bime"] || [optNameToChange isEqualToString:@"b-pyramid"] || [optNameToChange isEqualToString:@"no-fast-pskip"] || [optNameToChange isEqualToString:@"no-dct-decimate"] || [optNameToChange isEqualToString:@"8x8dct"] )            {
                if ([sender state] == 0)
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@""]];                    
                }
                else
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                        [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender state]]]];
                }
            }
            else if ([optNameToChange isEqualToString:@"cabac"])
            {
                if ([sender state] == 1)
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@""]];                                        
                }
                else
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                        [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender state]]]];                    
                }
            }            
            else
            {
                [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@=%@", 
                    [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender indexOfSelectedItem]-1]]];
            }
        }
        else
        {
            if ([optNameToChange isEqualToString:@"me"])
            {
                switch ([sender indexOfSelectedItem])
                {   
                    case 1:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"dia"]]];
                         break;

                    case 2:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"hex"]]];
                         break;

                    case 3:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"umh"]]];
                         break;

                    case 4:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"esa"]]];
                         break;

                    default:
                         break;
                }
            }
            else if ([optNameToChange isEqualToString:@"direct"])
            {
                switch ([sender indexOfSelectedItem])
                {   
                    case 1:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"none"]]];
                         break;

                    case 2:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"spatial"]]];
                         break;

                    case 3:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"temporal"]]];
                         break;

                    case 4:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"auto"]]];
                         break;

                    default:
                         break;
                }
            }
            else if ([optNameToChange isEqualToString:@"analyse"])
            {
                switch ([sender indexOfSelectedItem])
                {   
                    case 1:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"none"]]];
                         break;

                    case 2:
                         [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", 
                             [NSString stringWithFormat:[fDisplayX264Options stringValue]],
                             [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"all"]]];
                         break;

                    default:
                         break;
                }
            }

            else if ([optNameToChange isEqualToString:@"merange"])
            {
                [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@",[NSString stringWithFormat:[fDisplayX264Options stringValue]], 
                    [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender indexOfSelectedItem]+3]]];
            }
            else if ([optNameToChange isEqualToString:@"deblock"])
            {
                [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@", [NSString stringWithFormat:[fDisplayX264Options stringValue]], [NSString stringWithFormat:optNameToChange], [NSString stringWithFormat:@"%d,%d", ([fX264optAlphaDeblockPopUp indexOfSelectedItem] != 0) ? [fX264optAlphaDeblockPopUp indexOfSelectedItem]-7 : 0, ([fX264optBetaDeblockPopUp indexOfSelectedItem] != 0) ? [fX264optBetaDeblockPopUp indexOfSelectedItem]-7 : 0]]];                
            }
            else if /*Boolean Switches*/ ([optNameToChange isEqualToString:@"mixed-refs"] || [optNameToChange isEqualToString:@"weightb"] || [optNameToChange isEqualToString:@"brdo"] || [optNameToChange isEqualToString:@"bime"] || [optNameToChange isEqualToString:@"b-pyramid"] || [optNameToChange isEqualToString:@"no-fast-pskip"] || [optNameToChange isEqualToString:@"no-dct-decimate"] || [optNameToChange isEqualToString:@"8x8dct"] )
            {
                if ([sender state] == 0)
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@",[NSString stringWithFormat:[fDisplayX264Options stringValue]]]];                    
                }
                else
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@",[NSString stringWithFormat:[fDisplayX264Options stringValue]], 
                        [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender state]]]];                
                }
            }
            else if ([optNameToChange isEqualToString:@"cabac"])
            {
                if ([sender state] == 1)
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@",[NSString stringWithFormat:[fDisplayX264Options stringValue]]]];                    
                }
                else
                {
                    [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@",[NSString stringWithFormat:[fDisplayX264Options stringValue]], 
                        [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender state]]]];
                }
            }
            else
            {
                [fDisplayX264Options setStringValue:[NSString stringWithFormat:@"%@:%@=%@",[NSString stringWithFormat:[fDisplayX264Options stringValue]], 
                    [NSString stringWithFormat:optNameToChange],[NSString stringWithFormat:@"%d",[sender indexOfSelectedItem]-1]]];
            }
        }
    }

    /* We now need to reset the opt widgets since we changed some stuff */		
    [self X264AdvancedOptionsSet:NULL];		
}


   /* We use this method to recreate new, updated factory
   presets */
- (IBAction)AddFactoryPresets:(id)sender
{
    /* First, we delete any existing built in presets */
    [self DeleteFactoryPresets: sender];
    /* Then, we re-create new built in presets programmatically CreateIpodOnlyPreset*/
    [UserPresets addObject:[self CreateNormalPreset]];
    [UserPresets addObject:[self CreateClassicPreset]];
    [UserPresets addObject:[self CreateQuickTimePreset]];
	[UserPresets addObject:[self CreateIpodLowPreset]];
	[UserPresets addObject:[self CreateIpodHighPreset]];
	[UserPresets addObject:[self CreateAppleTVPreset]];
    [UserPresets addObject:[self CreateiPhonePreset]];
	[UserPresets addObject:[self CreatePSThreePreset]];
	[UserPresets addObject:[self CreatePSPPreset]];
	[UserPresets addObject:[self CreateFilmPreset]];
    [UserPresets addObject:[self CreateTelevisionPreset]];
    [UserPresets addObject:[self CreateAnimationPreset]];
    [UserPresets addObject:[self CreateBedlamPreset]];
    
    [self AddPreset];
}
- (IBAction)DeleteFactoryPresets:(id)sender
{
    //int status;
    NSEnumerator *enumerator = [UserPresets objectEnumerator];
	id tempObject;
    
	//NSNumber *index;
    NSMutableArray *tempArray;


        tempArray = [NSMutableArray array];
        /* we look here to see if the preset is we move on to the next one */
        while ( tempObject = [enumerator nextObject] )  
		{
			/* if the preset is "Factory" then we put it in the array of
			presets to delete */
			if ([[tempObject objectForKey:@"Type"] intValue] == 0)
			{
				[tempArray addObject:tempObject];
			}
        }
        
        [UserPresets removeObjectsInArray:tempArray];
        [tableView reloadData];
        [self savePreset];   

}

- (IBAction) ShowAddPresetPanel: (id) sender
{
    /* Deselect the currently selected Preset if there is one*/
		[tableView deselectRow:[tableView selectedRow]];

	/* Populate the preset picture settings popup here */
	[fPresetNewPicSettingsPopUp removeAllItems];
	[fPresetNewPicSettingsPopUp addItemWithTitle:@"None"];
	[fPresetNewPicSettingsPopUp addItemWithTitle:@"Current"];
	[fPresetNewPicSettingsPopUp addItemWithTitle:@"Source Maximum (post source scan)"];
	[fPresetNewPicSettingsPopUp selectItemAtIndex: 0];	
	
		/* Erase info from the input fields fPresetNewDesc*/
	[fPresetNewName setStringValue: @""];
	[fPresetNewDesc setStringValue: @""];
	/* Show the panel */
	[NSApp beginSheet: fAddPresetPanel modalForWindow: fWindow
        modalDelegate: NULL didEndSelector: NULL contextInfo: NULL];
    [NSApp runModalForWindow: fAddPresetPanel];
    [NSApp endSheet: fAddPresetPanel];
    [fAddPresetPanel orderOut: self];
	
	
}
- (IBAction) CloseAddPresetPanel: (id) sender
{
	[NSApp stopModal];
}


- (IBAction)AddUserPreset:(id)sender
{

    /* Here we create a custom user preset */
	[UserPresets addObject:[self CreatePreset]];
	/* Erase info from the input fields */
	[fPresetNewName setStringValue: @""];
	[fPresetNewDesc setStringValue: @""];
	/* We stop the modal window for the new preset */
	[NSApp stopModal];
    [self AddPreset];
	

}
- (void)AddPreset
{

	
	/* We Sort the Presets By Factory or Custom */
	NSSortDescriptor * presetTypeDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"Type" 
                                                    ascending:YES] autorelease];
	/* We Sort the Presets Alphabetically by name */
	NSSortDescriptor * presetNameDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"PresetName" 
                                                    ascending:YES selector:@selector(caseInsensitiveCompare:)] autorelease];
	NSArray *sortDescriptors=[NSArray arrayWithObjects:presetTypeDescriptor,presetNameDescriptor,nil];
	NSArray *sortedArray=[UserPresets sortedArrayUsingDescriptors:sortDescriptors];
	[UserPresets setArray:sortedArray];
	
	
	/* We Reload the New Table data for presets */
    [tableView reloadData];
   /* We save all of the preset data here */
    [self savePreset];
}

- (IBAction)InsertPreset:(id)sender
{
    int index = [tableView selectedRow];
    [UserPresets insertObject:[self CreatePreset] atIndex:index];
    [tableView reloadData];
    [self savePreset];
}

- (NSDictionary *)CreatePreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:[fPresetNewName stringValue] forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:[fPresetNewPicSettingsPopUp indexOfSelectedItem]] forKey:@"UsesPictureSettings"];
	/* Get New Preset Description from the field in the AddPresetPanel*/
	[preset setObject:[fPresetNewDesc stringValue] forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:[fDstFormatPopUp titleOfSelectedItem] forKey:@"FileFormat"];
	/* Chapter Markers fCreateChapterMarkers*/
	[preset setObject:[NSNumber numberWithInt:[fCreateChapterMarkers state]] forKey:@"ChapterMarkers"];
	/* Allow Mpeg4 64 bit formatting +4GB file sizes */
	[preset setObject:[NSNumber numberWithInt:[fDstMpgLargeFileCheck state]] forKey:@"Mp4LargeFile"];
	/* Codecs */
	[preset setObject:[fDstCodecsPopUp titleOfSelectedItem] forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:[fVidEncoderPopUp titleOfSelectedItem] forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:[fDisplayX264Options stringValue] forKey:@"x264Option"];
	
	[preset setObject:[NSNumber numberWithInt:[fVidQualityMatrix selectedRow]] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:[fVidBitrateField stringValue] forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:[fVidRatePopUp titleOfSelectedItem] forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:[fVidGrayscaleCheck state]] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:[fVidTwoPassCheck state]] forKey:@"VideoTwoPass"];
	/* Turbo 2 pass Encoding fVidTurboPassCheck*/
	[preset setObject:[NSNumber numberWithInt:[fVidTurboPassCheck state]] forKey:@"VideoTurboTwoPass"];
	/*Picture Settings*/
	hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:fTitle->job->width] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:fTitle->job->height] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:fTitle->job->keep_ratio] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:fTitle->job->deinterlace] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:fTitle->job->pixel_ratio] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	//[preset setObject:[NSNumber numberWithInt:[[fPictureController fCropMatrix] selectedRow]] forKey:@"PictureAutoCrop"];

	[preset setObject:[NSNumber numberWithInt:job->crop[0]] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:job->crop[1]] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:job->crop[2]] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:job->crop[3]] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:[fAudRatePopUp titleOfSelectedItem] forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:[fAudBitratePopUp titleOfSelectedItem] forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:[fSubPopUp titleOfSelectedItem] forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateIpodLowPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-iPod Low-Res" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's low resolution settings for the iPod. Optimized for great playback on the iPod screen, with smaller file size." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 iPod)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"keyint=300:keyint-min=30:bframes=0:cabac=0:ref=1:vbv-maxrate=768:vbv-bufsize=2000:analyse=all:me=umh:subme=6:no-fast-pskip=1" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"700" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:320] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}


- (NSDictionary *)CreateIpodHighPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-iPod High-Res" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's high resolution settings for the iPod. Good video quality, great for viewing on a TV using your iPod" forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 iPod)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"keyint=300:keyint-min=30:bframes=0:cabac=0:ref=1:vbv-maxrate=1500:vbv-bufsize=2000:analyse=all:me=umh:subme=6:no-fast-pskip=1" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1500" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:640] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateAppleTVPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-AppleTV" forKey:@"PresetName"];
	/*Set whether or not this is a user preset where 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:2] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for the AppleTV. Provides a good balance between quality and file size, and optimizes performance." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
	/* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String (We can use this to tweak the appleTV output)*/
	[preset setObject:@"bframes=3:ref=1:subme=5:me=umh:no-fast-pskip=1:trellis=2" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"2500" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	/* For AppleTV we only want to retain UsesMaxPictureSettings
	which depend on the source dvd picture settings, so we don't
	record the current dvd's picture info since it will vary from
	source to source*/
	//hb_job_t * job = fTitle->job;
	//hb_job_t * job = title->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreatePSThreePreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-PS3" forKey:@"PresetName"];
	/*Set whether or not this is a user preset where 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:2] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for the Sony PlayStation 3." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
	/* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String (We can use this to tweak the appleTV output)*/
	[preset setObject:@"level=41:subme=5:me=umh" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"2500" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	/* For PS3 we only want to retain UsesMaxPictureSettings
	which depend on the source dvd picture settings, so we don't
	record the current dvd's picture info since it will vary from
	source to source*/
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}
- (NSDictionary *)CreatePSPPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-PSP" forKey:@"PresetName"];
	/*Set whether or not this is a user preset where 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for the Sony PlayStation Portable." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
	/* Codecs */
	[preset setObject:@"MPEG-4 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"FFmpeg" forKey:@"VideoEncoder"];
	/* x264 Option String (We can use this to tweak the appleTV output)*/
	[preset setObject:@"" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1024" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	/* For PS3 we only want to retain UsesMaxPictureSettings
	which depend on the source dvd picture settings, so we don't
	record the current dvd's picture info since it will vary from
	source to source*/
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:@"368" forKey:@"PictureWidth"];
	[preset setObject:@"208" forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"128" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateNormalPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-Normal" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's normal, default settings." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"ref=2:mixed-refs:bframes=3:weightb:bime:direct=auto:subme=5:me=umh:trellis=1" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1500" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateClassicPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-Classic" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's traditional, faster, lower-quality settings." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:0] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"MPEG-4 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"FFmpeg" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1000" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateFilmPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-Film" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's preset for feature films." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MKV file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AC-3 Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"ref=6:mixed-refs:bframes=3:bime:weightb:b-rdo:direct=auto:b-pyramid:me=umh:subme=7:me-range=24:analyse=all:8x8dct:trellis=2:no-fast-pskip" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"2000" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateTelevisionPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-Television" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for video from television." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MKV file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"ref=3:mixed-refs:bframes=9:bime:weightb:direct=auto:b-pyramid:me=umh:subme=6:me-range=24:analyse=all:8x8dct:trellis=2:nr=150:no-fast-pskip" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1300" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"29.97" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateAnimationPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-Animation" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for cartoons, anime, and CGI." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MKV file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"ref=9:mixed-refs:bframes=13:bime:weightb:b-rdo:direct=auto:b-pyramid:me=umh:subme=7:me-range=24:analyse=all:8x8dct:trellis=2:nr=150:no-fast-pskip:filter=2,2" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1000" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"29.97" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateQuickTimePreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-QuickTime" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for use with QuickTime." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"ref=6:mixed-refs:bframes=3:bime:weightb:b-rdo:direct-auto:me=umh:subme=7:me-range=24:analyse=all:8x8dct:trellis=2:no-fast-pskip" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"2000" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateBedlamPreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-Bedlam" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings maxed out for slowest encoding and highest quality. Use at your own risk. So slow it's not just insane...it's a trip to the looney bin." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MKV file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AC-3 Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 Main)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"ref=16:mixed-refs:bframes=13:bime:weightb:b-rdo:direct=auto:b-pyramid:me=umh:subme=7:me-range=64:analyse=all:8x8dct:trellis=2:no-fast-pskip:no-dct-decimate:filter=-2,-1" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"1800" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureAutoCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (NSDictionary *)CreateiPhonePreset
{
    NSMutableDictionary *preset = [[NSMutableDictionary alloc] init];
	/* Get the New Preset Name from the field in the AddPresetPanel */
    [preset setObject:@"HB-iPhone" forKey:@"PresetName"];
	/*Set whether or not this is a user preset or factory 0 is factory, 1 is user*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Type"];
	/*Set whether or not this is default, at creation set to 0*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"Default"];
	/*Get the whether or not to apply pic settings in the AddPresetPanel*/
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"UsesPictureSettings"];
	/* Get the New Preset Description from the field in the AddPresetPanel */
    [preset setObject:@"HandBrake's settings for the iPhone." forKey:@"PresetDescription"];
	/* File Format */
    [preset setObject:@"MP4 file" forKey:@"FileFormat"];
	/* Chapter Markers*/
	 [preset setObject:[NSNumber numberWithInt:1] forKey:@"ChapterMarkers"];
    /* Codecs */
	[preset setObject:@"AVC/H.264 Video / AAC Audio" forKey:@"FileCodecs"];
	/* Video encoder */
	[preset setObject:@"x264 (h.264 iPod)" forKey:@"VideoEncoder"];
	/* x264 Option String */
	[preset setObject:@"cabac=0:ref=1:analyse=all:me=umh:subme=6:no-fast-pskip=1:trellis=2" forKey:@"x264Option"];
	/* Video quality */
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"VideoQualityType"];
	[preset setObject:[fVidTargetSizeField stringValue] forKey:@"VideoTargetSize"];
	[preset setObject:@"960" forKey:@"VideoAvgBitrate"];
	[preset setObject:[NSNumber numberWithFloat:[fVidQualitySlider floatValue]] forKey:@"VideoQualitySlider"];
	
	/* Video framerate */
	[preset setObject:@"Same as source" forKey:@"VideoFramerate"];
	/* GrayScale */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoGrayScale"];
	/* 2 Pass Encoding */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"VideoTwoPass"];
	
	/*Picture Settings*/
	//hb_job_t * job = fTitle->job;
	/* Basic Picture Settings */
	/* Use Max Picture settings for whatever the dvd is.*/
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"UsesMaxPictureSettings"];
	[preset setObject:[NSNumber numberWithInt:480] forKey:@"PictureWidth"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureHeight"];
	[preset setObject:[NSNumber numberWithInt:1] forKey:@"PictureKeepRatio"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureDeinterlace"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PicturePAR"];
	/* Set crop settings here */
	/* The Auto Crop Matrix in the Picture Window autodetects differences in crop settings */
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureTopCrop"];
    [preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureBottomCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureLeftCrop"];
	[preset setObject:[NSNumber numberWithInt:0] forKey:@"PictureRightCrop"];
	
	/*Audio*/
	/* Audio Sample Rate*/
	[preset setObject:@"48" forKey:@"AudioSampleRate"];
	/* Audio Bitrate Rate*/
	[preset setObject:@"160" forKey:@"AudioBitRate"];
	/* Subtitles*/
	[preset setObject:@"None" forKey:@"Subtitles"];
	

    [preset autorelease];
    return preset;

}

- (IBAction)DeletePreset:(id)sender
{
    int status;
    NSEnumerator *enumerator;
    NSNumber *index;
    NSMutableArray *tempArray;
    id tempObject;
    
    if ( [tableView numberOfSelectedRows] == 0 )
        return;
    /* Alert user before deleting preset */
	/* Comment out for now, tie to user pref eventually */

    //NSBeep();
    status = NSRunAlertPanel(@"Warning!", @"Are you sure that you want to delete the selected preset?", @"OK", @"Cancel", nil);
    
    if ( status == NSAlertDefaultReturn ) {
        enumerator = [tableView selectedRowEnumerator];
        tempArray = [NSMutableArray array];
        
        while ( (index = [enumerator nextObject]) ) {
            tempObject = [UserPresets objectAtIndex:[index intValue]];
            [tempArray addObject:tempObject];
        }
        
        [UserPresets removeObjectsInArray:tempArray];
        [tableView reloadData];
        [self savePreset];   
    }
}
- (IBAction)tableViewSelected:(id)sender
{
    /* Since we cannot disable the presets tableView in terms of clickability
	   we will use the enabled state of the add presets button to determine whether
	   or not clicking on a preset will do anything */
	if ([fPresetsAdd isEnabled])
	{
		
		/* we get the chosen preset from the UserPresets array */
		chosenPreset = [UserPresets objectAtIndex:[sender selectedRow]];
		curUserPresetChosenNum = [sender selectedRow];
		/* we set the preset display field in main window here */
		[fPresetSelectedDisplay setStringValue: [NSString stringWithFormat: @"%@",[chosenPreset valueForKey:@"PresetName"]]];
		/* File Format */
		[fDstFormatPopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"FileFormat"]]];
		[self FormatPopUpChanged: NULL];
		
		/* Chapter Markers*/
		[fCreateChapterMarkers setState:[[chosenPreset objectForKey:@"ChapterMarkers"] intValue]];
		/* Allow Mpeg4 64 bit formatting +4GB file sizes */
		[fDstMpgLargeFileCheck setState:[[chosenPreset objectForKey:@"Mp4LargeFile"] intValue]];
		/* Codecs */
		[fDstCodecsPopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"FileCodecs"]]];
		[self CodecsPopUpChanged: NULL];
		/* Video encoder */
		[fVidEncoderPopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"VideoEncoder"]]];
		
		/* We can show the preset options here in the gui if we want to
			so we check to see it the user has specified it in the prefs */
		[fDisplayX264Options setStringValue: [NSString stringWithFormat:[chosenPreset valueForKey:@"x264Option"]]];

		[self X264AdvancedOptionsSet:NULL];
		
		/* Lets run through the following functions to get variables set there */
		[self EncoderPopUpChanged: NULL];
		
		[self CalculateBitrate: NULL];
		
		/* Video quality */
		[fVidQualityMatrix selectCellAtRow:[[chosenPreset objectForKey:@"VideoQualityType"] intValue] column:0];
		
		[fVidTargetSizeField setStringValue: [NSString stringWithFormat:[chosenPreset valueForKey:@"VideoTargetSize"]]];
		[fVidBitrateField setStringValue: [NSString stringWithFormat:[chosenPreset valueForKey:@"VideoAvgBitrate"]]];
		
		[fVidQualitySlider setFloatValue: [[chosenPreset valueForKey:@"VideoQualitySlider"] floatValue]];
		[self VideoMatrixChanged: NULL];
		
		/* Video framerate */
		[fVidRatePopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"VideoFramerate"]]];

		/* GrayScale */
		[fVidGrayscaleCheck setState:[[chosenPreset objectForKey:@"VideoGrayScale"] intValue]];
		
		/* 2 Pass Encoding */
		[fVidTwoPassCheck setState:[[chosenPreset objectForKey:@"VideoTwoPass"] intValue]];
		[self TwoPassCheckboxChanged: NULL];
		/* Turbo 1st pass for 2 Pass Encoding */
		[fVidTurboPassCheck setState:[[chosenPreset objectForKey:@"VideoTurboTwoPass"] intValue]];
		
		/*Audio*/
		
		/* Audio Sample Rate*/
		[fAudRatePopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"AudioSampleRate"]]];
		/* Audio Bitrate Rate*/
		[fAudBitratePopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"AudioBitRate"]]];
		/*Subtitles*/
		[fSubPopUp selectItemWithTitle: [NSString stringWithFormat:[chosenPreset valueForKey:@"Subtitles"]]];
		
		/* Picture Settings */
		/* Look to see if we apply these here in objectForKey:@"UsesPictureSettings"] */
		if ([[chosenPreset objectForKey:@"UsesPictureSettings"]  intValue] > 0)
		{
			hb_job_t * job = fTitle->job;
			/* Check to see if we should use the max picture setting for the current title*/
			if ([[chosenPreset objectForKey:@"UsesPictureSettings"]  intValue] == 2 || [[chosenPreset objectForKey:@"UsesMaxPictureSettings"]  intValue] == 1)
			{
				/* Use Max Picture settings for whatever the dvd is.*/
				[self RevertPictureSizeToMax: NULL];
				job->keep_ratio = [[chosenPreset objectForKey:@"PictureKeepRatio"]  intValue];
				if (job->keep_ratio == 1)
				{
					hb_fix_aspect( job, HB_KEEP_WIDTH );
				}
				job->pixel_ratio = [[chosenPreset objectForKey:@"PicturePAR"]  intValue];
			}
			else
			{
				job->width = [[chosenPreset objectForKey:@"PictureWidth"]  intValue];
				job->height = [[chosenPreset objectForKey:@"PictureHeight"]  intValue];
				job->keep_ratio = [[chosenPreset objectForKey:@"PictureKeepRatio"]  intValue];
				if (job->keep_ratio == 1)
				{
					hb_fix_aspect( job, HB_KEEP_WIDTH );
				}
				job->pixel_ratio = [[chosenPreset objectForKey:@"PicturePAR"]  intValue];
				/* AutoCrop is in preset, then use the autocrop settings for each dvd */
				if ([[chosenPreset objectForKey:@"PictureAutoCrop"]  intValue] == 1)
				{
				[fPicSettingAutoCrop setStringValue: [NSString stringWithFormat:
				@"%d", 1]];
				job->crop[0] = [[chosenPreset objectForKey:@"PictureTopCrop"]  intValue];
				job->crop[1] = [[chosenPreset objectForKey:@"PictureBottomCrop"]  intValue];
				job->crop[2] = [[chosenPreset objectForKey:@"PictureLeftCrop"]  intValue];
				job->crop[3] = [[chosenPreset objectForKey:@"PictureRightCrop"]  intValue];
				}
				else /* if custom crop has been saved in preset, use the saved custom cropping regardless of the source */
				{
				[fPicSettingAutoCrop setStringValue: [NSString stringWithFormat:
				@"%d", 0]];
				job->crop[0] = [[chosenPreset objectForKey:@"PictureTopCrop"]  intValue];
				job->crop[1] = [[chosenPreset objectForKey:@"PictureBottomCrop"]  intValue];
				job->crop[2] = [[chosenPreset objectForKey:@"PictureLeftCrop"]  intValue];
				job->crop[3] = [[chosenPreset objectForKey:@"PictureRightCrop"]  intValue];
				}
			}
			[self CalculatePictureSizing: NULL]; 
		}
		



}
}



- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [UserPresets count];
}

/* we use this to determine display characteristics for
each table cell based on content currently only used to
show the built in presets in a blue font. */
- (void)tableView:(NSTableView *)aTableView
 willDisplayCell:(id)aCell 
 forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    NSDictionary *userPresetDict = [UserPresets objectAtIndex:rowIndex];
	NSColor *fontColor;
	NSColor *shadowColor;
	/* First, we check to see if its a selected row, if so, we use white since its highlighted in blue */
	if ([[aTableView selectedRowIndexes] containsIndex:rowIndex] && ([tableView editedRow] != rowIndex))
	{
		
		fontColor = [NSColor whiteColor];
		shadowColor = [NSColor colorWithDeviceRed:(127.0/255.0) green:(140.0/255.0) blue:(160.0/255.0) alpha:1.0];
	}
	else
	{
		/* We set the properties of unselected rows */
		/* if built-in preset (defined by "type" == 0) we use a blue font */
		if ([[userPresetDict objectForKey:@"Type"] intValue] == 0)
		{
			fontColor = [NSColor blueColor];
		}
		else // User created preset, use a black font
		{
			fontColor = [NSColor blackColor];
		}
		shadowColor = nil;
	}
	[aCell setTextColor:fontColor];
	/* this shadow stuff (like mail app) for some reason looks crappy, commented out
	temporarily in case we want to resurrect it */
	/*
	NSShadow *shadow = [[NSShadow alloc] init];
	NSSize shadowOffset = { width: 1.0, height: -1.5};
	[shadow setShadowOffset:shadowOffset];
	[shadow setShadowColor:shadowColor];
	[shadow set];
	*/
	
}
/* Method to display tooltip with the description for each preset, if available */
- (NSString *)tableView:(NSTableView *)aTableView toolTipForCell:(NSCell *)aCell 
                   rect:(NSRectPointer)aRect tableColumn:(NSTableColumn *)aTableColumn
                    row:(int)rowIndex mouseLocation:(NSPoint)aPos
{
     /* initialize the tooltip contents variable */
	 NSString *loc_tip;
     /* if there is a description for the preset, we show it in the tooltip */
	 if ([[UserPresets objectAtIndex:rowIndex] valueForKey:@"PresetDescription"])
	 {
	 loc_tip = [NSString stringWithFormat: @"%@",[[UserPresets objectAtIndex:rowIndex] valueForKey:@"PresetDescription"]];
	 return (loc_tip);
	 }
	 else
	 {
	 loc_tip = @"No description available";
	 }
	 return (loc_tip);

}

- (id)tableView:(NSTableView *)aTableView
      objectValueForTableColumn:(NSTableColumn *)aTableColumn
      row:(int)rowIndex
{
id theRecord, theValue;
    
    theRecord = [UserPresets objectAtIndex:rowIndex];
    theValue = [theRecord objectForKey:[aTableColumn identifier]];
    return theValue;
}

// NSTableDataSource method that we implement to edit values directly in the table...
- (void)tableView:(NSTableView *)aTableView
        setObjectValue:(id)anObject
        forTableColumn:(NSTableColumn *)aTableColumn
        row:(int)rowIndex
{
    id theRecord;
    
    theRecord = [UserPresets objectAtIndex:rowIndex];
    [theRecord setObject:anObject forKey:@"PresetName"];
    /* We Sort the Presets By Factory or Custom */
	NSSortDescriptor * presetTypeDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"Type" 
                                                    ascending:YES] autorelease];
		/* We Sort the Presets Alphabetically by name */
	NSSortDescriptor * presetNameDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"PresetName" 
                                                    ascending:YES selector:@selector(caseInsensitiveCompare:)] autorelease];
	NSArray *sortDescriptors=[NSArray arrayWithObjects:presetTypeDescriptor,presetNameDescriptor,nil];
    NSArray *sortedArray=[UserPresets sortedArrayUsingDescriptors:sortDescriptors];
	[UserPresets setArray:sortedArray];
	/* We Reload the New Table data for presets */
    [tableView reloadData];
   /* We save all of the preset data here */
    [self savePreset];
}


- (void)savePreset
{
    [UserPresets writeToFile:UserPresetsFile atomically:YES];

}



- (void) controlTextDidBeginEditing: (NSNotification *) notification
{
    [self CalculateBitrate: NULL];
}

- (void) controlTextDidEndEditing: (NSNotification *) notification
{
    [self CalculateBitrate: NULL];
}

- (void) controlTextDidChange: (NSNotification *) notification
{
    [self CalculateBitrate: NULL];
}

- (IBAction) OpenHomepage: (id) sender
{
    [[NSWorkspace sharedWorkspace] openURL: [NSURL
        URLWithString:@"http://handbrake.m0k.org/"]];
}

- (IBAction) OpenForums: (id) sender
{
    [[NSWorkspace sharedWorkspace] openURL: [NSURL
        URLWithString:@"http://handbrake.m0k.org/forum/"]];
}
- (IBAction) OpenUserGuide: (id) sender
{
    [[NSWorkspace sharedWorkspace] openURL: [NSURL
        URLWithString:@"http://handbrake.m0k.org/trac/wiki/HandBrakeGuide"]];
}

/**
 * Shows debug output window.
 */
- (IBAction)showDebugOutputPanel:(id)sender
{
    [outputPanel showOutputPanel:sender];
}

/**
 * Creates preferences controller, shows preferences window modally, and
 * releases the controller after user has closed the window.
 */
- (IBAction)showPreferencesWindow:(id)sender
{
    HBPreferencesController *controller = [[HBPreferencesController alloc] init];
    [controller runModal:nil];
    [controller release];
}

@end
