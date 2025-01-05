//
//  MLSoundsTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <monalxmpp/HelperTools.h>
#import "MLSoundsTableViewController.h"
#import "MLSettingCell.h"
#import <monalxmpp/MLImageManager.h>
@import AVFoundation;

@interface MLSoundsTableViewController ()
@property (nonatomic, strong) NSArray* soundList;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, strong) AVAudioPlayer* audioPlayer;
@end

@implementation MLSoundsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Sounds", @"");
    self.soundList = @[
        @"System Sound",
        @"Morse",
        @"Xylophone",
        @"Bloop",
        @"Bing",
        @"Pipa",
        @"Water",
        @"Forest",
        @"Echo",
        @"Area 51",
        @"Wood",
        @"Chirp",
        @"Sonar",
    ];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return 2;
}

-(NSInteger) tableView:(UITableView*) tableView numberOfRowsInSection:(NSInteger) section
{
    if(section == 0)
        return 1;
    else
        return (NSInteger)self.soundList.count;
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    if(section == 1)
        return NSLocalizedString(@"Select sounds that are played with new message notifications. Default is Xylophone.", @"");
    return nil;
}

-(NSString*) tableView:(UITableView*) tableView titleForFooterInSection:(NSInteger) section
{
    if(section == 1)
        return NSLocalizedString(@"Sounds courtesy Emrah", @"");
    return nil;
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(indexPath.section == 0)
    {
        MLSettingCell* cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
        cell.parent = self;
        cell.switchEnabled = YES;
        cell.defaultKey = @"Sound";
        cell.textLabel.text = NSLocalizedString(@"Play Sounds", @"");
        return cell;
    }
    else
    {
        UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"soundCell"];
        cell.textLabel.text = self.soundList[(NSUInteger)indexPath.row];
        NSString* filename = [NSString stringWithFormat:@"alert%ld", (long)indexPath.row];
        if(
            (indexPath.row == 0 && [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"] == nil) ||
            [filename isEqualToString:[[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"]]
        )
        {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            self.selectedIndex = indexPath.row;
        }
        else
        {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }
}


-(void) playSound:(NSInteger ) index
{
    NSString* filename = [NSString stringWithFormat:@"alert%ld", (long)index];
    NSURL* url = [[NSBundle mainBundle] URLForResource:filename withExtension:@"aif" subdirectory:@"AlertSounds"];
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    [self.audioPlayer play];
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if(indexPath.section==0)
        return;
    
    NSString* filename = nil;
    if(indexPath.row > 0)
    {
        [self playSound:indexPath.row];
        filename = [NSString stringWithFormat:@"alert%ld", (long)indexPath.row];
        [[HelperTools defaultsDB] setObject:filename forKey:@"AlertSoundFile"];
    }
    else
        [[HelperTools defaultsDB] removeObjectForKey:@"AlertSoundFile"];
    NSIndexPath* old = [NSIndexPath indexPathForRow:self.selectedIndex inSection:1];
    self.selectedIndex = indexPath.row;
    NSArray* rows = @[old, indexPath];
    [tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
}


@end

