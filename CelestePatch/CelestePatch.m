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

static NSURL *CelesteRewriteURL(NSURL *url) {
    if (!url) return url;
    NSString *host = url.host;
    if (!host) return url;

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

static NSURLRequest *CelesteRewriteRequest(NSURLRequest *req) {
    if (!req) return req;
    NSURL *newURL = CelesteRewriteURL(req.URL);
    if (newURL == req.URL) return req;

    NSMutableURLRequest *m = [req mutableCopy];
    m.URL = newURL;
    return [m copy];
}


static void CelesteSwap(Class cls, SEL orig, SEL swz) {
    Method a = class_getInstanceMethod(cls, orig);
    Method b = class_getInstanceMethod(cls, swz);
    if (!a || !b) {
        NSLog(@"[Celeste] swap miss on %s -> %s / %s",
              class_getName(cls), sel_getName(orig), sel_getName(swz));
        return;
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
}

@interface NSURL (Celeste)
@end
@implementation NSURL (Celeste)
+ (instancetype)celeste_URLWithString:(NSString *)str {
    NSURL *u = [self celeste_URLWithString:str];
    NSURL *r = CelesteRewriteURL(u);
    return r ?: u;
}
+ (instancetype)celeste_URLWithString:(NSString *)str relativeToURL:(NSURL *)base {
    NSURL *u = [self celeste_URLWithString:str relativeToURL:base];
    NSURL *r = CelesteRewriteURL(u);
    return r ?: u;
}
@end

@interface NSURLRequest (Celeste)
@end
@implementation NSURLRequest (Celeste)
- (instancetype)celeste_initWithURL:(NSURL *)url {
    NSURL *r = CelesteRewriteURL(url);
    return [self celeste_initWithURL:r ?: url];
}
- (instancetype)celeste_initWithURL:(NSURL *)url
                        cachePolicy:(NSURLRequestCachePolicy)cp
                    timeoutInterval:(NSTimeInterval)to {
    NSURL *r = CelesteRewriteURL(url);
    return [self celeste_initWithURL:r ?: url cachePolicy:cp timeoutInterval:to];
}
@end

@interface NSMutableURLRequest (Celeste)
@end
@implementation NSMutableURLRequest (Celeste)
- (void)celeste_setURL:(NSURL *)url {
    NSURL *r = CelesteRewriteURL(url);
    [self celeste_setURL:r ?: url];
}
@end

@interface NSURLSession (Celeste)
@end
@implementation NSURLSession (Celeste)

- (NSURLSessionDataTask *)celeste_dataTaskWithURL:(NSURL *)url {
    return [self celeste_dataTaskWithURL:CelesteRewriteURL(url) ?: url];
}
- (NSURLSessionDataTask *)celeste_dataTaskWithURL:(NSURL *)url
                                completionHandler:(void(^)(NSData *, NSURLResponse *, NSError *))h {
    return [self celeste_dataTaskWithURL:CelesteRewriteURL(url) ?: url completionHandler:h];
}
- (NSURLSessionDataTask *)celeste_dataTaskWithRequest:(NSURLRequest *)req {
    return [self celeste_dataTaskWithRequest:CelesteRewriteRequest(req)];
}
- (NSURLSessionDataTask *)celeste_dataTaskWithRequest:(NSURLRequest *)req
                                    completionHandler:(void(^)(NSData *, NSURLResponse *, NSError *))h {
    return [self celeste_dataTaskWithRequest:CelesteRewriteRequest(req) completionHandler:h];
}

- (NSURLSessionDownloadTask *)celeste_downloadTaskWithURL:(NSURL *)url {
    return [self celeste_downloadTaskWithURL:CelesteRewriteURL(url) ?: url];
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
    return [self celeste_webSocketTaskWithURL:CelesteRewriteURL(url) ?: url];
}
- (id)celeste_webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protos {
    return [self celeste_webSocketTaskWithURL:CelesteRewriteURL(url) ?: url protocols:protos];
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

__attribute__((constructor))
static void CelestePatchInit(void) {
    @autoreleasepool {
        NSLog(@"[Celeste] bootstrap");

        Class URL   = [NSURL class];
        Class Req   = [NSURLRequest class];
        Class MReq  = [NSMutableURLRequest class];
        Class Sess  = [NSURLSession class];

        // NSURL class methods
        Method a, b;
        a = class_getClassMethod(URL, @selector(URLWithString:));
        b = class_getClassMethod(URL, @selector(celeste_URLWithString:));
        if (a && b) method_exchangeImplementations(a, b);
        a = class_getClassMethod(URL, @selector(URLWithString:relativeToURL:));
        b = class_getClassMethod(URL, @selector(celeste_URLWithString:relativeToURL:));
        if (a && b) method_exchangeImplementations(a, b);

        // NSURLRequest
        CelesteSwap(Req,  @selector(initWithURL:),
                          @selector(celeste_initWithURL:));
        CelesteSwap(Req,  @selector(initWithURL:cachePolicy:timeoutInterval:),
                          @selector(celeste_initWithURL:cachePolicy:timeoutInterval:));
        CelesteSwap(MReq, @selector(setURL:),
                          @selector(celeste_setURL:));

        // NSURLSession data/download/upload/websocket
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

        NSLog(@"[Celeste] bootstrap done, %zu redirects active", kRedirectsCount);
    }
}
