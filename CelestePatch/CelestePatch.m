// for iOS arm64, injected in discord.app via insert_dylib
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef struct {
    const char *from;
    const char *to;
    BOOL matchSubdomains;  // if yes also match *.from
} HostRedirect;

static const HostRedirect kRedirects[] = {
    { "gateway.discord.gg",     "alpha-gateway.celeste.gg", NO  },
    { "cdn.discordapp.com",     "cdn.celeste.gg",           NO  },
    { "cdn.discord.com",        "cdn.celeste.gg",           NO  },
    { "media.discordapp.net",   "media.celeste.gg",         NO  },
    { "images.discordapp.net",  "media.celeste.gg",         NO  },
    { "discord.com",            "alpha.celeste.gg",         YES },
    { "discordapp.com",         "alpha.celeste.gg",         YES },
};
static const size_t kRedirectsCount = sizeof(kRedirects) / sizeof(kRedirects[0]);

static NSString *CelesteRewriteHost(NSString *host) {
    if (host.length == 0) return host;
    const char *h = host.UTF8String;
    size_t hlen = strlen(h);

    for (size_t i = 0; i < kRedirectsCount; i++) {
        const HostRedirect *r = &kRedirects[i];
        size_t flen = strlen(r->from);

        if (hlen == flen && strcasecmp(h, r->from) == 0) {
            return [NSString stringWithUTF8String:r->to];
        }
        if (r->matchSubdomains && hlen > flen + 1) {
            if (h[hlen - flen - 1] == '.' &&
                strcasecmp(h + hlen - flen, r->from) == 0) {
                return [NSString stringWithUTF8String:r->to];
            }
        }
    }
    return nil;
}

static BOOL CelesteIsCdnHost(NSString *host) {
    static const char *kCdnHosts[] = {
        "cdn.discordapp.com", "cdn.discord.com",
        "media.discordapp.net", "images.discordapp.net",
    };
    const char *h = host.UTF8String;
    for (size_t i = 0; i < sizeof(kCdnHosts) / sizeof(kCdnHosts[0]); i++) {
        if (strcasecmp(h, kCdnHosts[i]) == 0) return YES;
    }
    return NO;
}

static BOOL CelesteIsCdnAssetBypass(NSString *host, NSString *path) {
    if (path.length == 0) return NO;
    if (!CelesteIsCdnHost(host)) return NO;

    static NSArray<NSString *> *kBypass = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kBypass = @[
            @"/assets/", @"/detectables/", @"/changelogs/", @"/badge-icons/",
            @"/discovery-splashes/", @"/hot-spots/", @"/embed/",
            @"/avatar-decoration-presets/", @"/clyde-ai/", @"/quests/",
            @"/build_overrides/", @"/streamer-mode-blocked-words/", @"/app-assets/",
            @"/app-icons/", @"/bad-domains/", @"/media/v1/collectibles-shop/",
        ];
    });
    for (NSString *p in kBypass) {
        if ([path hasPrefix:p]) return YES;
    }
    return NO;
}

static BOOL CelesteIsHostOnlyCdn(NSString *host, NSString *path) {
    if (!CelesteIsCdnHost(host)) return NO;
    return path.length == 0 || [path isEqualToString:@"/"];
}

// DCDBundleUpdater fetches https://discord.com/ios/<CFBundleShortVersionString>/manifest.json;
// celeste answers that path with the web app (303 then html 200), which the updater applies as an empty ota
static BOOL CelesteIsOtaUpdate(NSURL *url, NSString *host) {
    if (host) {
        return [host caseInsensitiveCompare:@"discord.com"] == NSOrderedSame && [url.path hasPrefix:@"/ios/"];
    }
    // the updater joins its url with pathWithComponents:, which may collapse https:// into a hostless https:/
    NSString *scheme = url.scheme;
    if (!scheme || [scheme caseInsensitiveCompare:@"https"] != NSOrderedSame) return NO;
    NSString *abs = url.absoluteString;
    return abs && [abs rangeOfString:@"discord.com/ios/" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSURL *CelesteBlockedOtaURL(void) {
    static NSURL *blocked;
    static dispatch_once_t once;
    // an unsupported scheme makes the task fail at once, the same path the updater takes offline
    dispatch_once(&once, ^{ blocked = [[NSURL alloc] initWithString:@"celeste-blocked://ota-disabled/manifest.json"]; });
    return blocked;
}

static NSURL *CelesteRewriteURL(NSURL *url) {
    if (!url) return url;
    NSString *host = url.host;

    if (CelesteIsOtaUpdate(url, host)) {
        NSLog(@"[Celeste] blocked ota request %@", url.absoluteString);
        return CelesteBlockedOtaURL();
    }
    if (!host) return url;

    if (CelesteIsCdnAssetBypass(host, url.path)) return url;
    if (CelesteIsHostOnlyCdn(host, url.path)) return url;
    if ([url.path hasPrefix:@"/ra/"]) return url;

    NSString *newHost = CelesteRewriteHost(host);
    if (!newHost) return url;

    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!c) return url;
    c.host = newHost;

    NSURL *rewritten = c.URL;
    if (!rewritten) return url;

#ifdef DEBUG
    NSLog(@"[Celeste] %@ -> %@", url.absoluteString, rewritten.absoluteString);
#endif
    return rewritten;
}

static NSURL *CelesteRewriteURLGuarded(NSURL *url);

static NSURLRequest *CelesteRewriteRequest(NSURLRequest *req) {
    if (!req) return req;
    NSURL *newURL = CelesteRewriteURLGuarded(req.URL);
    if (newURL == req.URL) return req;

    NSMutableURLRequest *m = [req mutableCopy];
    m.URL = newURL;
    return [m copy];
}


static unsigned gCelesteHooked, gCelesteMissed;

static BOOL CelesteSwap(Class cls, SEL orig, SEL swz) {
    Method a = cls ? class_getInstanceMethod(cls, orig) : NULL;
    Method b = cls ? class_getInstanceMethod(cls, swz) : NULL;
    if (!a || !b) {
        NSLog(@"[Celeste] swap miss on %s -> %s / %s",
              cls ? class_getName(cls) : "(nil)", sel_getName(orig), sel_getName(swz));
        gCelesteMissed++;
        return NO;
    }
    if (class_addMethod(cls,
                        orig,
                        method_getImplementation(b),
                        method_getTypeEncoding(b))) {
        class_replaceMethod(cls,
                            swz,
                            method_getImplementation(a),
                            method_getTypeEncoding(a));
    } else {
        method_exchangeImplementations(a, b);
    }
    gCelesteHooked++;
    return YES;
}

static BOOL CelesteSwapClass(Class cls, SEL orig, SEL swz) {
    Method a = cls ? class_getClassMethod(cls, orig) : NULL;
    Method b = cls ? class_getClassMethod(cls, swz) : NULL;
    if (!a || !b) {
        NSLog(@"[Celeste] class swap miss on %s -> %s / %s",
              cls ? class_getName(cls) : "(nil)", sel_getName(orig), sel_getName(swz));
        gCelesteMissed++;
        return NO;
    }
    method_exchangeImplementations(a, b);
    gCelesteHooked++;
    return YES;
}

// NSURLComponents.URL may build its result through +URLWithString:, which would re-enter the rewrite
static __thread BOOL tCelesteInRewrite;

static NSURL *CelesteRewriteURLGuarded(NSURL *url) {
    if (tCelesteInRewrite) return url;
    tCelesteInRewrite = YES;
    NSURL *r = CelesteRewriteURL(url);
    tCelesteInRewrite = NO;
    return r;
}

@interface NSURL (Celeste)
@end
@implementation NSURL (Celeste)
+ (instancetype)celeste_URLWithString:(NSString *)str {
    NSURL *u = [self celeste_URLWithString:str];
    NSURL *r = CelesteRewriteURLGuarded(u);
    return r ?: u;
}
+ (instancetype)celeste_URLWithString:(NSString *)str relativeToURL:(NSURL *)base {
    NSURL *u = [self celeste_URLWithString:str relativeToURL:base];
    NSURL *r = CelesteRewriteURLGuarded(u);
    return r ?: u;
}
@end

@interface NSURLRequest (Celeste)
@end
@implementation NSURLRequest (Celeste)
- (instancetype)celeste_initWithURL:(NSURL *)url {
    NSURL *r = CelesteRewriteURLGuarded(url);
    return [self celeste_initWithURL:r ?: url];
}
- (instancetype)celeste_initWithURL:(NSURL *)url
                        cachePolicy:(NSURLRequestCachePolicy)cp
                    timeoutInterval:(NSTimeInterval)to {
    NSURL *r = CelesteRewriteURLGuarded(url);
    return [self celeste_initWithURL:r ?: url cachePolicy:cp timeoutInterval:to];
}
@end

@interface NSMutableURLRequest (Celeste)
@end
@implementation NSMutableURLRequest (Celeste)
- (void)celeste_setURL:(NSURL *)url {
    NSURL *r = CelesteRewriteURLGuarded(url);
    [self celeste_setURL:r ?: url];
}
@end

@interface NSURLSession (Celeste)
@end
@implementation NSURLSession (Celeste)

- (NSURLSessionDataTask *)celeste_dataTaskWithURL:(NSURL *)url {
    return [self celeste_dataTaskWithURL:CelesteRewriteURLGuarded(url) ?: url];
}
- (NSURLSessionDataTask *)celeste_dataTaskWithURL:(NSURL *)url
                                completionHandler:(void(^)(NSData *, NSURLResponse *, NSError *))h {
    return [self celeste_dataTaskWithURL:CelesteRewriteURLGuarded(url) ?: url completionHandler:h];
}
- (NSURLSessionDataTask *)celeste_dataTaskWithRequest:(NSURLRequest *)req {
    return [self celeste_dataTaskWithRequest:CelesteRewriteRequest(req)];
}
- (NSURLSessionDataTask *)celeste_dataTaskWithRequest:(NSURLRequest *)req
                                    completionHandler:(void(^)(NSData *, NSURLResponse *, NSError *))h {
    return [self celeste_dataTaskWithRequest:CelesteRewriteRequest(req) completionHandler:h];
}

- (NSURLSessionDownloadTask *)celeste_downloadTaskWithURL:(NSURL *)url {
    return [self celeste_downloadTaskWithURL:CelesteRewriteURLGuarded(url) ?: url];
}
- (NSURLSessionDownloadTask *)celeste_downloadTaskWithRequest:(NSURLRequest *)req {
    return [self celeste_downloadTaskWithRequest:CelesteRewriteRequest(req)];
}

- (NSURLSessionUploadTask *)celeste_uploadTaskWithRequest:(NSURLRequest *)req
                                                 fromData:(NSData *)data {
    return [self celeste_uploadTaskWithRequest:CelesteRewriteRequest(req) fromData:data];
}
- (NSURLSessionUploadTask *)celeste_uploadTaskWithRequest:(NSURLRequest *)req
                                                 fromFile:(NSURL *)file {
    return [self celeste_uploadTaskWithRequest:CelesteRewriteRequest(req) fromFile:file];
}

- (id /*NSURLSessionWebSocketTask*/)celeste_webSocketTaskWithURL:(NSURL *)url {
    return [self celeste_webSocketTaskWithURL:CelesteRewriteURLGuarded(url) ?: url];
}
- (id)celeste_webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protos {
    return [self celeste_webSocketTaskWithURL:CelesteRewriteURLGuarded(url) ?: url protocols:protos];
}
- (id)celeste_webSocketTaskWithRequest:(NSURLRequest *)req {
    return [self celeste_webSocketTaskWithRequest:CelesteRewriteRequest(req)];
}
@end

@interface CelesteChallengeInterceptor : NSObject <NSURLSessionDelegate>
@end
@implementation CelesteChallengeInterceptor
+ (void)handleChallenge:(NSURLAuthenticationChallenge *)c
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,
                                  NSURLCredential *))completion {
    NSString *host = c.protectionSpace.host;
    NSString *newHost = CelesteRewriteHost(host);
    if (newHost == nil) {
        completion(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    SecTrustRef trust = c.protectionSpace.serverTrust;
    if (trust) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:trust];
        completion(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }
    completion(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}
@end

@interface NSFileManager (Celeste)
@end
@implementation NSFileManager (Celeste)
// a sideloaded build never holds group.com.hammerandchisel.discord, so the system returns nil
- (NSURL *)celeste_containerURLForSecurityApplicationGroupIdentifier:(NSString *)group {
    NSURL *u = [self celeste_containerURLForSecurityApplicationGroupIdentifier:group];
    if (u) return u;
    NSURL *docs = [[self URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    if (!docs) {
        NSLog(@"[Celeste] app group %@ unavailable and no documents directory", group);
        return nil;
    }
    NSURL *fallback = [docs URLByAppendingPathComponent:@"AppGroup" isDirectory:YES];
    NSError *err = nil;
    if (![self createDirectoryAtURL:fallback withIntermediateDirectories:YES attributes:nil error:&err]) {
        NSLog(@"[Celeste] app group fallback for %@ failed: %@", group, err);
        return nil;
    }
    return fallback;
}
@end

__attribute__((constructor))
static void CelestePatchInit(void) {
    @autoreleasepool {
        NSLog(@"[Celeste] bootstrap");

        Class URL   = objc_getClass("NSURL");
        Class Req   = objc_getClass("NSURLRequest");
        Class MReq  = objc_getClass("NSMutableURLRequest");
        Class Sess  = objc_getClass("NSURLSession");
        Class FM    = objc_getClass("NSFileManager");

        CelesteSwapClass(URL, @selector(URLWithString:),
                              @selector(celeste_URLWithString:));
        CelesteSwapClass(URL, @selector(URLWithString:relativeToURL:),
                              @selector(celeste_URLWithString:relativeToURL:));

        CelesteSwap(Req,  @selector(initWithURL:),
                          @selector(celeste_initWithURL:));
        CelesteSwap(Req,  @selector(initWithURL:cachePolicy:timeoutInterval:),
                          @selector(celeste_initWithURL:cachePolicy:timeoutInterval:));
        CelesteSwap(MReq, @selector(setURL:),
                          @selector(celeste_setURL:));

        CelesteSwap(Sess, @selector(dataTaskWithURL:),
                          @selector(celeste_dataTaskWithURL:));
        CelesteSwap(Sess, @selector(dataTaskWithURL:completionHandler:),
                          @selector(celeste_dataTaskWithURL:completionHandler:));
        CelesteSwap(Sess, @selector(dataTaskWithRequest:),
                          @selector(celeste_dataTaskWithRequest:));
        CelesteSwap(Sess, @selector(dataTaskWithRequest:completionHandler:),
                          @selector(celeste_dataTaskWithRequest:completionHandler:));
        CelesteSwap(Sess, @selector(downloadTaskWithURL:),
                          @selector(celeste_downloadTaskWithURL:));
        CelesteSwap(Sess, @selector(downloadTaskWithRequest:),
                          @selector(celeste_downloadTaskWithRequest:));
        CelesteSwap(Sess, @selector(uploadTaskWithRequest:fromData:),
                          @selector(celeste_uploadTaskWithRequest:fromData:));
        CelesteSwap(Sess, @selector(uploadTaskWithRequest:fromFile:),
                          @selector(celeste_uploadTaskWithRequest:fromFile:));
        CelesteSwap(Sess, @selector(webSocketTaskWithURL:),
                          @selector(celeste_webSocketTaskWithURL:));
        CelesteSwap(Sess, @selector(webSocketTaskWithURL:protocols:),
                          @selector(celeste_webSocketTaskWithURL:protocols:));
        CelesteSwap(Sess, @selector(webSocketTaskWithRequest:),
                          @selector(celeste_webSocketTaskWithRequest:));

        CelesteSwap(FM,   @selector(containerURLForSecurityApplicationGroupIdentifier:),
                          @selector(celeste_containerURLForSecurityApplicationGroupIdentifier:));

        NSLog(@"[Celeste] bootstrap done, %zu redirects, %u hooks installed, %u missed",
              kRedirectsCount, gCelesteHooked, gCelesteMissed);
    }
}
