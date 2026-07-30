// SlopNetWizard — the one calm path from "nothing" to "you can ask for work".
//
// Setup used to be a panel of controls in Settings: correct, but it asked a
// beginner to work out the order for themselves. This is the same machinery
// in a straight line — welcome, server, prepare the server, install the
// private local guide, mention a coding app, done — with one thing to read
// and one thing to press on each screen.
//
// Long jobs do not run inside this window. The wizard steps aside and the
// main console runs them, because those scripts ask real questions (a server
// password, "install and test it?") and the console is where a person can see
// and answer them. When a job finishes the launcher brings the wizard back at
// the next step, so nothing has to be found again.
//
// It is resumable on purpose: a server that is already prepared is not
// prepared twice, and a guide that has already passed its proof is not
// downloaded again.

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SlopNetWizardStep) {
    SlopNetWizardStepWelcome = 0,
    SlopNetWizardStepServer,        // address, login name, port
    SlopNetWizardStepServerSetup,   // the guided VPS preparation run
    SlopNetWizardStepGuide,         // IBM Granite: capacity, approve, install, proof
    SlopNetWizardStepCodingApp,     // optional, and only after the two above
    SlopNetWizardStepReady,
};

@class SlopNetWizard;

@protocol SlopNetWizardDelegate <NSObject>
/// Remember these details, then prepare the server in the main console.
- (void)wizard:(SlopNetWizard *)wizard
 connectToHost:(NSString *)host
          port:(NSString *)port
          user:(NSString *)user;
/// Install and prove the private local guide, in the main console. The script
/// asks its own questions there — capacity, then approval — before it
/// downloads anything.
- (void)wizard:(SlopNetWizard *)wizard installGuideModel:(NSString *)model;
/// Keep these details without starting anything (used when a step only edits
/// the connection fields).
- (void)wizard:(SlopNetWizard *)wizard rememberHost:(NSString *)host
          port:(NSString *)port user:(NSString *)user;
/// Sign in to the coding app on the server, in the main console.
- (void)wizardSignInToCodingApp:(SlopNetWizard *)wizard;
/// Open Settings, where the coding apps on the server are listed.
- (void)wizardOpenSettings:(SlopNetWizard *)wizard;
/// Finish: close up and put the person in Chat with the private guide.
- (void)wizardStartChat:(SlopNetWizard *)wizard;
/// Finish without starting a chat.
- (void)wizardDidFinish:(SlopNetWizard *)wizard;
@end

@interface SlopNetWizard : NSWindowController

@property(nonatomic, weak) id<SlopNetWizardDelegate> delegate;
@property(nonatomic, readonly) SlopNetWizardStep step;

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                 serverReady:(BOOL)serverReady
                  guideReady:(BOOL)guideReady;

/// The step this person should land on: the first thing that is not done yet.
+ (SlopNetWizardStep)resumeStepForServerReady:(BOOL)serverReady
                                   guideReady:(BOOL)guideReady;

- (void)presentFrom:(NSWindow *)parent;

/// Tell the wizard what is true NOW. It used to take these once at birth, so
/// a step could keep insisting the server was not prepared after a run that
/// prepared it — and going Back showed the same stale screen.
- (void)updateServerReady:(BOOL)serverReady guideReady:(BOOL)guideReady;
- (void)showStep:(SlopNetWizardStep)step;

/// Read-only look at the server's private runtime account: is it there, is
/// llama installed, which model has already passed its proof, and how much
/// storage and memory are free. Starts nothing, downloads nothing, opens no
/// port. Keys in the result: runtime, llama, model, disk, memory, cache.
/// `error` is set instead when the server could not be asked.
+ (void)probeGuideOnHost:(NSString *)host
                    port:(NSString *)port
                    user:(NSString *)user
              completion:(void (^)(NSDictionary<NSString *, NSString *> *values,
                                   NSString *error))completion;

@end
