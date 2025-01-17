// Copyright 2013 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/chrome/browser/ui/settings/settings_navigation_controller.h"

#include "base/mac/foundation_util.h"
#include "components/strings/grit/components_strings.h"
#include "ios/chrome/browser/browser_state/chrome_browser_state.h"
#include "ios/chrome/browser/sync/sync_setup_service.h"
#include "ios/chrome/browser/sync/sync_setup_service_factory.h"
#import "ios/chrome/browser/ui/icons/chrome_icon.h"
#import "ios/chrome/browser/ui/keyboard/UIKeyCommand+Chrome.h"
#import "ios/chrome/browser/ui/material_components/utils.h"
#import "ios/chrome/browser/ui/settings/autofill/autofill_credit_card_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/autofill/autofill_profile_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/google_services/accounts_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/google_services/google_services_settings_coordinator.h"
#import "ios/chrome/browser/ui/settings/google_services/google_services_settings_view_controller.h"
#import "ios/chrome/browser/ui/settings/import_data_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/password/passwords_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/settings_root_collection_view_controller.h"
#import "ios/chrome/browser/ui/settings/settings_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/sync/sync_encryption_passphrase_table_view_controller.h"
#import "ios/chrome/browser/ui/settings/utils/settings_utils.h"
#include "ios/chrome/browser/ui/ui_feature_flags.h"
#include "ios/chrome/browser/ui/util/ui_util.h"
#import "ios/chrome/browser/ui/util/uikit_ui_util.h"
#import "ios/chrome/common/ui_util/constraints_ui_util.h"
#include "ios/chrome/grit/ios_strings.h"
#import "ios/public/provider/chrome/browser/chrome_browser_provider.h"
#import "ios/public/provider/chrome/browser/user_feedback/user_feedback_provider.h"
#include "ui/base/l10n/l10n_util_mac.h"

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

NSString* const kSettingsDoneButtonId = @"kSettingsDoneButtonId";

@interface SettingsNavigationController () <
    GoogleServicesSettingsCoordinatorDelegate,
    UIAdaptivePresentationControllerDelegate,
    UINavigationControllerDelegate>

// Google services settings coordinator.
@property(nonatomic, strong)
    GoogleServicesSettingsCoordinator* googleServicesSettingsCoordinator;

// Current UIViewController being presented by this Navigation Controller.
// If nil it means the Navigation Controller is not presenting anything, or the
// VC being presented doesn't conform to
// UIAdaptivePresentationControllerDelegate.
@property(nonatomic, weak)
    UIViewController<UIAdaptivePresentationControllerDelegate>*
        currentPresentedViewController;

// The SettingsNavigationControllerDelegate for this NavigationController.
@property(nonatomic, weak) id<SettingsNavigationControllerDelegate>
    settingsNavigationDelegate;

@end

@implementation SettingsNavigationController {
  ios::ChromeBrowserState* mainBrowserState_;  // weak
}

#pragma mark - SettingsNavigationController methods.

+ (SettingsNavigationController*)
newSettingsMainControllerWithBrowserState:(ios::ChromeBrowserState*)browserState
                                 delegate:
                                     (id<SettingsNavigationControllerDelegate>)
                                         delegate {
  SettingsTableViewController* controller = [[SettingsTableViewController alloc]
      initWithBrowserState:browserState
                dispatcher:[delegate dispatcherForSettings]];
  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];
  [controller navigationItem].rightBarButtonItem = [nc doneButton];
  return nc;
}

+ (SettingsNavigationController*)
newAccountsController:(ios::ChromeBrowserState*)browserState
             delegate:(id<SettingsNavigationControllerDelegate>)delegate {
  AccountsTableViewController* controller =
      [[AccountsTableViewController alloc] initWithBrowserState:browserState
                                      closeSettingsOnAddAccount:YES];
  controller.dispatcher = [delegate dispatcherForSettings];
  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];
  [controller navigationItem].leftBarButtonItem = [nc cancelButton];
  return nc;
}

+ (SettingsNavigationController*)
    newGoogleServicesController:(ios::ChromeBrowserState*)browserState
                       delegate:
                           (id<SettingsNavigationControllerDelegate>)delegate {
  // GoogleServicesSettings uses a coordinator to be presented, therefore the
  // view controller is not accessible. Prefer creating a
  // |SettingsNavigationController| with a nil root view controller and then
  // use the coordinator to push the GoogleServicesSettings as the first
  // root view controller.
  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:nil
                    browserState:browserState
                        delegate:delegate];
  [nc showGoogleServices];
  return nc;
}

+ (SettingsNavigationController*)
    newUserFeedbackController:(ios::ChromeBrowserState*)browserState
                     delegate:(id<SettingsNavigationControllerDelegate>)delegate
           feedbackDataSource:(id<UserFeedbackDataSource>)dataSource
                   dispatcher:(id<ApplicationCommands>)dispatcher {
  DCHECK(ios::GetChromeBrowserProvider()
             ->GetUserFeedbackProvider()
             ->IsUserFeedbackEnabled());
  UIViewController* controller =
      ios::GetChromeBrowserProvider()
          ->GetUserFeedbackProvider()
          ->CreateViewController(dataSource, dispatcher);
  DCHECK(controller);
  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];
  // If the controller overrides overrideUserInterfaceStyle, respect that in the
  // SettingsNavigationController.
  if (@available(iOS 13.0, *)) {
    nc.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle;
  }
  return nc;
}

+ (SettingsNavigationController*)
newSyncEncryptionPassphraseController:(ios::ChromeBrowserState*)browserState
                             delegate:(id<SettingsNavigationControllerDelegate>)
                                          delegate {
  SyncEncryptionPassphraseTableViewController* controller =
      [[SyncEncryptionPassphraseTableViewController alloc]
          initWithBrowserState:browserState];
  controller.dispatcher = [delegate dispatcherForSettings];
  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];
  [controller navigationItem].leftBarButtonItem = [nc cancelButton];
  return nc;
}

+ (SettingsNavigationController*)
newSavePasswordsController:(ios::ChromeBrowserState*)browserState
                  delegate:(id<SettingsNavigationControllerDelegate>)delegate {
  PasswordsTableViewController* controller =
      [[PasswordsTableViewController alloc] initWithBrowserState:browserState];
  controller.dispatcher = [delegate dispatcherForSettings];

  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];
  [controller navigationItem].rightBarButtonItem = [nc doneButton];

  // Make sure the cancel button is always present, as the Save Passwords screen
  // isn't just shown from Settings.
  [controller navigationItem].leftBarButtonItem = [nc cancelButton];
  return nc;
}

+ (SettingsNavigationController*)
newImportDataController:(ios::ChromeBrowserState*)browserState
               delegate:(id<SettingsNavigationControllerDelegate>)delegate
     importDataDelegate:(id<ImportDataControllerDelegate>)importDataDelegate
              fromEmail:(NSString*)fromEmail
                toEmail:(NSString*)toEmail
             isSignedIn:(BOOL)isSignedIn {
  UIViewController* controller =
      [[ImportDataTableViewController alloc] initWithDelegate:importDataDelegate
                                                    fromEmail:fromEmail
                                                      toEmail:toEmail
                                                   isSignedIn:isSignedIn];

  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];

  // Make sure the cancel button is always present, as the Save Passwords screen
  // isn't just shown from Settings.
  [controller navigationItem].leftBarButtonItem = [nc cancelButton];
  return nc;
}

+ (SettingsNavigationController*)
newAutofillProfilleController:(ios::ChromeBrowserState*)browserState
                     delegate:
                         (id<SettingsNavigationControllerDelegate>)delegate {
  AutofillProfileTableViewController* controller =
      [[AutofillProfileTableViewController alloc]
          initWithBrowserState:browserState];
  controller.dispatcher = [delegate dispatcherForSettings];

  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];

  // Make sure the cancel button is always present, as the Autofill screen
  // isn't just shown from Settings.
  [controller navigationItem].leftBarButtonItem = [nc cancelButton];
  return nc;
}

+ (SettingsNavigationController*)
newAutofillCreditCardController:(ios::ChromeBrowserState*)browserState
                       delegate:
                           (id<SettingsNavigationControllerDelegate>)delegate {
  AutofillCreditCardTableViewController* controller =
      [[AutofillCreditCardTableViewController alloc]
          initWithBrowserState:browserState];
  controller.dispatcher = [delegate dispatcherForSettings];

  SettingsNavigationController* nc = [[SettingsNavigationController alloc]
      initWithRootViewController:controller
                    browserState:browserState
                        delegate:delegate];

  // Make sure the cancel button is always present, as the Autofill screen
  // isn't just shown from Settings.
  [controller navigationItem].leftBarButtonItem = [nc cancelButton];
  return nc;
}

#pragma mark - Lifecycle

- (instancetype)
initWithRootViewController:(UIViewController*)rootViewController
              browserState:(ios::ChromeBrowserState*)browserState
                  delegate:(id<SettingsNavigationControllerDelegate>)delegate {
  DCHECK(browserState);
  DCHECK(!browserState->IsOffTheRecord());
  self = [super initWithRootViewController:rootViewController];
  if (self) {
    mainBrowserState_ = browserState;
    _settingsNavigationDelegate = delegate;
    self.modalPresentationStyle = UIModalPresentationFormSheet;
    // Set the presentationController delegate. This is used for swipe down to
    // dismiss. This needs to be set after the modalPresentationStyle.
    if (@available(iOS 13, *)) {
      self.presentationController.delegate = self;
    }
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  if (base::FeatureList::IsEnabled(kSettingsRefresh)) {
    self.navigationBar.backgroundColor = UIColor.whiteColor;
  }
  self.navigationBar.prefersLargeTitles = YES;
  self.navigationBar.accessibilityIdentifier = @"SettingNavigationBar";
  // Set the NavigationController delegate.
  self.delegate = self;
}

#pragma mark - Public

- (UIBarButtonItem*)doneButton {
  UIBarButtonItem* item = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                           target:self
                           action:@selector(closeSettings)];
  item.accessibilityIdentifier = kSettingsDoneButtonId;
  return item;
}

- (void)cleanUpSettings {
  // Notify all controllers of a Settings dismissal.
  for (UIViewController* controller in [self viewControllers]) {
    if ([controller respondsToSelector:@selector(settingsWillBeDismissed)]) {
      [controller performSelector:@selector(settingsWillBeDismissed)];
    }
  }

  // GoogleServicesSettingsCoordinator must be stopped before dismissing the
  // sync settings view.
  [self stopGoogleServicesSettingsCoordinator];

  // Reset the delegate to prevent any queued transitions from attempting to
  // close the settings.
  self.settingsNavigationDelegate = nil;
}

- (void)closeSettings {
  [self.settingsNavigationDelegate closeSettings];
}

- (void)popViewControllerOrCloseSettingsAnimated:(BOOL)animated {
  if (self.viewControllers.count > 1) {
    // Pop the top view controller to reveal the view controller underneath.
    [self popViewControllerAnimated:animated];
  } else {
    // If there is only one view controller in the navigation stack,
    // simply close settings.
    [self closeSettings];
  }
}

- (UIViewController*)popViewControllerAnimated:(BOOL)animated {
  UIViewController* poppedViewController =
      [super popViewControllerAnimated:animated];
  if ([poppedViewController
          respondsToSelector:@selector(viewControllerWasPopped)]) {
    [poppedViewController performSelector:@selector(viewControllerWasPopped)];
  }
  return poppedViewController;
}

#pragma mark - Private

// Creates an autoreleased "Cancel" button that cancels the settings when
// tapped.
- (UIBarButtonItem*)cancelButton {
  UIBarButtonItem* cancelButton = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                           target:self
                           action:@selector(closeSettings)];
  return cancelButton;
}

// Pushes a GoogleServicesSettingsViewController on this settings navigation
// controller. Does nothing id the top view controller is already of type
// |GoogleServicesSettingsViewController|.
- (void)showGoogleServices {
  if ([self.topViewController
          isKindOfClass:[GoogleServicesSettingsViewController class]]) {
    // The top view controller is already the Google services settings panel.
    // No need to open it.
    return;
  }
  self.googleServicesSettingsCoordinator =
      [[GoogleServicesSettingsCoordinator alloc]
          initWithBaseViewController:self
                        browserState:mainBrowserState_
                                mode:GoogleServicesSettingsModeSettings];
  self.googleServicesSettingsCoordinator.dispatcher =
      [self.settingsNavigationDelegate dispatcherForSettings];
  self.googleServicesSettingsCoordinator.navigationController = self;
  self.googleServicesSettingsCoordinator.delegate = self;
  [self.googleServicesSettingsCoordinator start];
}

// Stops the underlying Google services settings coordinator if it exists.
- (void)stopGoogleServicesSettingsCoordinator {
  [self.googleServicesSettingsCoordinator stop];
  self.googleServicesSettingsCoordinator = nil;
}

#pragma mark - GoogleServicesSettingsCoordinatorDelegate

- (void)googleServicesSettingsCoordinatorDidRemove:
    (GoogleServicesSettingsCoordinator*)coordinator {
  DCHECK_EQ(self.googleServicesSettingsCoordinator, coordinator);
  [self stopGoogleServicesSettingsCoordinator];
}

#pragma mark - UIAdaptivePresentationControllerDelegate

- (BOOL)presentationControllerShouldDismiss:
    (UIPresentationController*)presentationController {
  if (@available(iOS 13, *)) {
    if ([self.currentPresentedViewController
            respondsToSelector:@selector
            (presentationControllerShouldDismiss:)]) {
      return [self.currentPresentedViewController
          presentationControllerShouldDismiss:presentationController];
    }
  }
  return NO;
}

- (void)presentationControllerDidDismiss:
    (UIPresentationController*)presentationController {
  if (@available(iOS 13, *)) {
    if ([self.currentPresentedViewController
            respondsToSelector:@selector(presentationControllerDidDismiss:)]) {
      [self.currentPresentedViewController
          presentationControllerDidDismiss:presentationController];
    }
  }
  // Call settingsWasDismissed to make sure any necessary cleanup is performed.
  [self.settingsNavigationDelegate settingsWasDismissed];
}

- (void)presentationControllerDidAttemptToDismiss:
    (UIPresentationController*)presentationController {
  if (@available(iOS 13, *)) {
    if ([self.currentPresentedViewController
            respondsToSelector:@selector
            (presentationControllerDidAttemptToDismiss:)]) {
      [self.currentPresentedViewController
          presentationControllerDidAttemptToDismiss:presentationController];
    }
  }
}

- (void)presentationControllerWillDismiss:
    (UIPresentationController*)presentationController {
  if (@available(iOS 13, *)) {
    if ([self.currentPresentedViewController
            respondsToSelector:@selector(presentationControllerWillDismiss:)]) {
      [self.currentPresentedViewController
          presentationControllerWillDismiss:presentationController];
    }
  }
}

#pragma mark - Accessibility

- (BOOL)accessibilityPerformEscape {
  UIViewController* poppedController = [self popViewControllerAnimated:YES];
  if (!poppedController)
    [self closeSettings];
  return YES;
}

#pragma mark - UINavigationController

// Ensures that the keyboard is always dismissed during a navigation transition.
- (BOOL)disablesAutomaticKeyboardDismissal {
  return NO;
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController*)navigationController
      willShowViewController:(UIViewController*)viewController
                    animated:(BOOL)animated {
  self.currentPresentedViewController = base::mac::ObjCCast<
      UIViewController<UIAdaptivePresentationControllerDelegate>>(
      viewController);
}

#pragma mark - UIResponder

- (NSArray*)keyCommands {
  if ([self presentedViewController]) {
    return nil;
  }
  __weak SettingsNavigationController* weakSelf = self;
  return @[
    [UIKeyCommand cr_keyCommandWithInput:UIKeyInputEscape
                           modifierFlags:Cr_UIKeyModifierNone
                                   title:nil
                                  action:^{
                                    [weakSelf closeSettings];
                                  }],
  ];
}

#pragma mark - ApplicationSettingsCommands

// TODO(crbug.com/779791) : Do not pass |baseViewController| through dispatcher.
- (void)showAccountsSettingsFromViewController:
    (UIViewController*)baseViewController {
  AccountsTableViewController* controller = [[AccountsTableViewController alloc]
           initWithBrowserState:mainBrowserState_
      closeSettingsOnAddAccount:NO];
  controller.dispatcher =
      [self.settingsNavigationDelegate dispatcherForSettings];
  [self pushViewController:controller animated:YES];
}

// TODO(crbug.com/779791) : Do not pass |baseViewController| through dispatcher.
- (void)showGoogleServicesSettingsFromViewController:
    (UIViewController*)baseViewController {
  [self showGoogleServices];
}

// TODO(crbug.com/779791) : Do not pass |baseViewController| through dispatcher.
- (void)showSyncPassphraseSettingsFromViewController:
    (UIViewController*)baseViewController {
  SyncEncryptionPassphraseTableViewController* controller =
      [[SyncEncryptionPassphraseTableViewController alloc]
          initWithBrowserState:mainBrowserState_];
  controller.dispatcher =
      [self.settingsNavigationDelegate dispatcherForSettings];
  [self pushViewController:controller animated:YES];
}

// TODO(crbug.com/779791) : Do not pass |baseViewController| through dispatcher.
- (void)showSavedPasswordsSettingsFromViewController:
    (UIViewController*)baseViewController {
  PasswordsTableViewController* controller =
      [[PasswordsTableViewController alloc]
          initWithBrowserState:mainBrowserState_];
  controller.dispatcher =
      [self.settingsNavigationDelegate dispatcherForSettings];
  [self pushViewController:controller animated:YES];
}

// TODO(crbug.com/779791) : Do not pass |baseViewController| through dispatcher.
- (void)showProfileSettingsFromViewController:
    (UIViewController*)baseViewController {
  AutofillProfileTableViewController* controller =
      [[AutofillProfileTableViewController alloc]
          initWithBrowserState:mainBrowserState_];
  controller.dispatcher =
      [self.settingsNavigationDelegate dispatcherForSettings];
  [self pushViewController:controller animated:YES];
}

// TODO(crbug.com/779791) : Do not pass |baseViewController| through dispatcher.
- (void)showCreditCardSettingsFromViewController:
    (UIViewController*)baseViewController {
  AutofillCreditCardTableViewController* controller =
      [[AutofillCreditCardTableViewController alloc]
          initWithBrowserState:mainBrowserState_];
  controller.dispatcher =
      [self.settingsNavigationDelegate dispatcherForSettings];
  [self pushViewController:controller animated:YES];
}

#pragma mark - Profile

- (ios::ChromeBrowserState*)mainBrowserState {
  return mainBrowserState_;
}

#pragma mark - UIResponder

- (BOOL)canBecomeFirstResponder {
  return YES;
}

@end
