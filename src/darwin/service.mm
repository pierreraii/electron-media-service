#include "module.h"
#include "napi.h"
#include "uv.h"
#import <AppKit/AppKit.h>

@implementation NativeMediaController
  DarwinMediaService* _service;

- (void)associateService:(DarwinMediaService*)service {
  _service = service;
}

- (MPRemoteCommandHandlerStatus)remotePlay {
    _service->Emit("play");
    return MPRemoteCommandHandlerStatusSuccess;
  }
- (MPRemoteCommandHandlerStatus)remotePause {
    _service->Emit("pause");
    return MPRemoteCommandHandlerStatusSuccess;
  }
- (MPRemoteCommandHandlerStatus)remoteTogglePlayPause {
    _service->Emit("playPause");
    return MPRemoteCommandHandlerStatusSuccess;
  }
- (MPRemoteCommandHandlerStatus)remoteNext {
    _service->Emit("next");
    return MPRemoteCommandHandlerStatusSuccess;
  }
- (MPRemoteCommandHandlerStatus)remotePrev {
    _service->Emit("previous");
    return MPRemoteCommandHandlerStatusSuccess;
  }

- (MPRemoteCommandHandlerStatus)remoteChangePlaybackPosition:(MPChangePlaybackPositionCommandEvent*)event {
  _service->EmitWithInt("seek", event.positionTime);
  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)move:(MPChangePlaybackPositionCommandEvent*)event {
  return MPRemoteCommandHandlerStatusSuccess;
}

@end

Napi::FunctionReference DarwinMediaService::constructor;

Napi::Object DarwinMediaService::Init(Napi::Env env, Napi::Object exports) {
  Napi::HandleScope scope(env);

  Napi::Function func = DefineClass(env, "DarwinMediaService", {
    InstanceMethod("hook", &DarwinMediaService::Hook),
    InstanceMethod("startService", &DarwinMediaService::StartService),
    InstanceMethod("stopService", &DarwinMediaService::StopService),
    InstanceMethod("setMetaData", &DarwinMediaService::SetMetaData)
  });

  constructor = Napi::Persistent(func);
  constructor.SuppressDestruct();

  exports.Set("DarwinMediaService", func);
  return exports;
}

DarwinMediaService::DarwinMediaService(const Napi::CallbackInfo& info) : Napi::ObjectWrap<DarwinMediaService>(info)  {}

static Napi::FunctionReference persistentCallback;
void DarwinMediaService::Hook(const Napi::CallbackInfo& info) {
  Napi::HandleScope scope(info.Env());

  persistentCallback = Napi::Persistent(info[0].As<Napi::Function>());
  persistentCallback.SuppressDestruct();
}

void DarwinMediaService::Emit(std::string eventName) {
  EmitWithInt(eventName, 0);
}

void DarwinMediaService::EmitWithInt(std::string eventName, int details) {
  if (persistentCallback != nullptr) {
    Napi::HandleScope scope(persistentCallback.Env());

    persistentCallback.Call({
      Napi::String::New(persistentCallback.Env(), eventName.c_str()),
      Napi::Number::New(persistentCallback.Env(), details)
    });
  }
}

void DarwinMediaService::StartService(const Napi::CallbackInfo& info) {
  Napi::HandleScope scope(info.Env());

  NativeMediaController* controller = [[NativeMediaController alloc] init];
  [controller associateService:this];

  MPRemoteCommandCenter *remoteCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  [remoteCommandCenter playCommand].enabled = true;
  [remoteCommandCenter pauseCommand].enabled = true;
  [remoteCommandCenter togglePlayPauseCommand].enabled = true;
  [remoteCommandCenter changePlaybackPositionCommand].enabled = true;
  [remoteCommandCenter nextTrackCommand].enabled = true;
  [remoteCommandCenter previousTrackCommand].enabled = true;

  [[remoteCommandCenter playCommand] addTarget:controller action:@selector(remotePlay)];
  [[remoteCommandCenter pauseCommand] addTarget:controller action:@selector(remotePause)];
  [[remoteCommandCenter togglePlayPauseCommand] addTarget:controller action:@selector(remoteTogglePlayPause)];
  [[remoteCommandCenter changePlaybackPositionCommand] addTarget:controller action:@selector(remoteChangePlaybackPosition:)];
  [[remoteCommandCenter nextTrackCommand] addTarget:controller action:@selector(remoteNext)];
  [[remoteCommandCenter previousTrackCommand] addTarget:controller action:@selector(remotePrev)];
}

void DarwinMediaService::StopService(const Napi::CallbackInfo& info) {
  Napi::HandleScope scope(info.Env());

  MPRemoteCommandCenter *remoteCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  [remoteCommandCenter playCommand].enabled = false;
  [remoteCommandCenter pauseCommand].enabled = false;
  [remoteCommandCenter togglePlayPauseCommand].enabled = false;
  [remoteCommandCenter changePlaybackPositionCommand].enabled = false;
}

void DarwinMediaService::SetMetaData(const Napi::CallbackInfo& info) {
  Napi::HandleScope scope(info.Env());

  std::string songTitle = info[0].As<Napi::String>().Utf8Value().c_str();
  std::string songArtist = info[1].As<Napi::String>().Utf8Value().c_str();
  std::string songAlbum = info[2].As<Napi::String>().Utf8Value().c_str();
  std::string songState = info[3].As<Napi::String>().Utf8Value().c_str();

  unsigned int songID = info[4].As<Napi::Number>();
  unsigned int currentTime = info[5].As<Napi::Number>();
  unsigned int duration = info[6].As<Napi::Number>();

  std::string artwork = info[7].As<Napi::String>().Utf8Value().c_str();  

  NSMutableDictionary *songInfo = [[NSMutableDictionary alloc] init];
  // [songInfo setObject:[NSString stringWithUTF8String:songTitle.c_str()] forKey:MPMediaItemPropertyTitle];
  [songInfo setObject:@"Some shfajhfjakshfksa" forKey:MPMediaItemPropertyTitle];
  [songInfo setObject:[NSString stringWithUTF8String:songArtist.c_str()] forKey:MPMediaItemPropertyArtist];
  [songInfo setObject:[NSString stringWithUTF8String:songAlbum.c_str()] forKey:MPMediaItemPropertyAlbumTitle];

  [songInfo setObject:[[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(512, 512) requestHandler:^NSImage * _Nonnull(CGSize size) {
    NSString *urlString = [NSString stringWithUTF8String:artwork.c_str()];
    NSURL *url = [NSURL URLWithString:urlString];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    NSLog(@"%@", image);
    return image;
  }] forKey:MPMediaItemPropertyArtwork];
  
  [songInfo setObject:[NSNumber numberWithFloat:0.5] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
  [songInfo setObject:[NSNumber numberWithFloat:5] forKey:MPMediaItemPropertyPlaybackDuration];
  [songInfo setObject:[NSNumber numberWithFloat:songID] forKey:MPMediaItemPropertyPersistentID];

  if (songState == "playi1ng") {
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStatePlaying;
  } else if (songState == "playing") {
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStatePaused;
  } else {
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStateStopped;
  }

  NSLog(@"%@", [[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo]);

  [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];

  NSLog(@"%@", [[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo]);
}