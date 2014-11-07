//
//  KKHttpOperation.m
//  Operation
//
//  Created by SunKe on 14/10/22.
//  Copyright (c) 2014年 Coneboy_K. All rights reserved.
//

#import "KKHttpOperation.h"
#import "KKBaseHttpQueue.h"
#import "KKHTTPRequstKit.h"


@interface KKHttpOperation () <NSURLConnectionDataDelegate>
{
    OSSpinLock _cancelHttpOperationSpinlock;

}

@property (nonatomic, assign) BOOL isCancelled;

@property (nonatomic ,strong) NSURLConnection *connection; // NSURLConnection 实例
@property (nonatomic, copy) NSMutableData *responseData; // 请求的数据
@property (nonatomic ,copy   ,readwrite) NSURLResponse *response;

@end


@implementation KKHttpOperation

@synthesize state = _state;

+ (void)networkRequestThreadEntryPoint:(id)__unused object {
    do {
        @autoreleasepool
        {
            [[NSRunLoop currentRunLoop] run];
            
            [[NSRunLoop currentRunLoop] runMode:NSRunLoopCommonModes
                                     beforeDate:[NSDate distantFuture]];
        }
    } while (YES);
    
}

+ (NSThread *)networkRequestThread {
    static NSThread *_networkRequestThread = nil;
    static dispatch_once_t oncePredicate;
    
    dispatch_once(&oncePredicate, ^{
        _networkRequestThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
        [_networkRequestThread start];
        [_networkRequestThread setName:@"COM.CONEBOY.HTTPCALLBACK"];

    });
    
    return _networkRequestThread;
}


#pragma mark - Getter&&Setter

- (KKHTTPOprerationState)state
{
    return (KKHTTPOprerationState)_state;
}

- (void)setState:(KKHTTPOprerationState)newState
{
    // K-V-C 来让queue来获取最近的state来控制
    switch (newState) {
        case KKHTTPOprerationState_Ready:
            [self willChangeValueForKey:@"isReady"];
            break;
        case KKHTTPOprerationState_Executing:
            [self willChangeValueForKey:@"isReady"];
            [self willChangeValueForKey:@"isExecuting"];
            break;
        case KKHTTPOprerationState_Finished:
            [self willChangeValueForKey:@"isExecuting"];
            [self willChangeValueForKey:@"isFinished"];
            break;
    }
    
    _state = newState;
    
    switch (newState) {
        case KKHTTPOprerationState_Ready:
            [self didChangeValueForKey:@"isReady"];
            break;
        case KKHTTPOprerationState_Executing:
            [self didChangeValueForKey:@"isReady"];
            [self didChangeValueForKey:@"isExecuting"];
            break;
        case KKHTTPOprerationState_Finished:
            [self didChangeValueForKey:@"isExecuting"];
            [self didChangeValueForKey:@"isFinished"];
            break;
    }
}


- (NSMutableData *)responseData
{
    if (!_responseData) {
        _responseData = [NSMutableData data];
    }
    
    return _responseData;
}

- (NSMutableDictionary *)headers
{
    if (!_headers) {
        _headers = [NSMutableDictionary dictionary];
    }
    
    return _headers;
}

- (NSMutableDictionary *)parameters
{
    if (!_parameters) {
        _parameters = [NSMutableDictionary dictionary];
    }
    return _parameters;
}


#pragma mark - make queryString

- (NSString *)queryParametersURL
{
    NSString *urlString = nil;
    if (self.parameters.count > 0) {
        urlString = [NSString stringWithFormat:@"%@?%@", self.url, [self queryString]];
    } else {
        urlString = [NSString stringWithFormat:@"%@", self.url];
    }
    return urlString;
}

- (NSString *)queryString
{
    NSMutableArray *encodedParameters = [NSMutableArray arrayWithCapacity:self.parameters.count];
    
    for (NSString *key in self.parameters) {
        NSString *value = self.parameters[key];
        
        if ([value isKindOfClass:[NSString class]]) {
            NSString *encodedKey   = [key stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *encodedValue = [value stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            [encodedParameters addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
        }
    }
    
    return [encodedParameters componentsJoinedByString:@"&"];
}

#pragma mark - NSMutableURLRequest

/**
 *  产生一个http request
 *
 *  @return NSMutableURLRequest 实例
 */
- (NSMutableURLRequest *)request
{
    // 拼接GET参数 POST不做处理。 为了统一URL传入格式
    if (self.method == HTTP_GET) {
        if (self.parameters) {
            self.url = [self queryParametersURL];
        }
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.url]];
    
    NSString *HttpMethodTmp = nil;
    switch (self.method) {
        case HTTP_GET:
            HttpMethodTmp = @"GET";
            break;
        case HTTP_POST:
            HttpMethodTmp = @"POST";
            break;
        default:
            HttpMethodTmp = @"GET";
            break;
    }
    
    request.HTTPMethod      = HttpMethodTmp;
    request.HTTPBody        = self.requestBody;
    request.timeoutInterval = self.timeoutInterval;
    request.cachePolicy     = NSURLRequestReloadIgnoringLocalCacheData;
    
    if (self.headers) {
        for (NSString *key in self.headers) {
            [request setValue:self.headers[key] forHTTPHeaderField:key];
        }
    }
    
    if (self.requestBody.length) {
        [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)self.requestBody.length] forHTTPHeaderField:@"Content-Length"];
    }
    
    return request;
}


#pragma mark - NSOperation config

-(void)main
{
    @autoreleasepool {
        [self start];
    }
}

- (void)start
{
    if(!self.isCancelled) {
    
        [self performSelector:@selector(operationDidStart)
                     onThread:[[self class] networkRequestThread]
                   withObject:nil
                waitUntilDone:NO
                        modes:@[NSRunLoopCommonModes]];
        
        self.state = KKHTTPOprerationState_Executing;
    } else {
        self.state = KKHTTPOprerationState_Finished;
    }
}

- (void)operationDidStart
{
    @synchronized(self) {
        self.connection = [[NSURLConnection alloc] initWithRequest:[self request]
                                                          delegate:self
                                                  startImmediately:NO];
        [self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [self.connection start];
    }
}
- (void)cancelConnection
{
    if (self.connection) {
        [self.connection cancel];
    }
    
    NSDictionary *userInfo = nil;
    [self performSelector:@selector(connection:didFailWithError:)
               withObject:self.connection
               withObject:[NSError errorWithDomain:NSURLErrorDomain
                                              code:NSURLErrorCancelled
                                          userInfo:userInfo]];
}


- (BOOL)isReady
{
    return (self.state == KKHTTPOprerationState_Ready && [super isReady]);
}

- (BOOL)isFinished
{
    return (self.state == KKHTTPOprerationState_Finished);
}

- (BOOL)isExecuting
{
    return (self.state == KKHTTPOprerationState_Executing);
}

- (void)cancel
{
    if([self isFinished])
        return;
    OSSpinLockLock(&_cancelHttpOperationSpinlock);
    
    [self performSelector:@selector(cancelConnection)
                 onThread:[[self class] networkRequestThread]
               withObject:nil
            waitUntilDone:NO
                    modes:@[NSRunLoopCommonModes]];
    
    self.isCancelled = YES;
   
    
    BOOL isNotFinish = (self.state == KKHTTPOprerationState_Executing ||
                        self.state == KKHTTPOprerationState_Ready);
        if(isNotFinish) {
            self.state = KKHTTPOprerationState_Finished;
        }
    
    OSSpinLockUnlock(&_cancelHttpOperationSpinlock);
    
    [super cancel];
}


+ (instancetype)loadRequestWithURL:(NSString *)url resultBlock:(KKHttpConnectionBlock)resultBlock
{
    KKHttpOperation *ucReq = [[[self class] alloc] initWithURL:url
                                                        method:HTTP_GET
                                                        header:nil
                                                    parameters:nil
                                                   requestBody:nil
                                               timeOutInterval:DEFAULTTIMEOUT
                                          completeOnMainThread:YES];
    
    [ucReq loadRequestWithResultBlock:resultBlock];
    
    return ucReq;
}


- (instancetype)initWithURL:(NSString *)url
                     method:(HTTPMETHOD)method
                     header:(NSMutableDictionary *)headers
                 parameters:(NSMutableDictionary *)parameters
                requestBody:(NSData *)requestBody
            timeOutInterval:(NSTimeInterval)timeoutInterval
       completeOnMainThread:(BOOL)completeOnMainThread
{
    self = [super init];
    
    if (self) {
        
        self.url = url;
        self.method = method;
        self.headers = headers;
        self.parameters = parameters;
        self.requestBody = requestBody;
        self.timeoutInterval = timeoutInterval;
        self.completeOnMainThread = completeOnMainThread;
        
        self.isCancelled = NO;
        self.state = KKHTTPOprerationState_Ready;
        _cancelHttpOperationSpinlock = OS_SPINLOCK_INIT;
    }
    
    return self;
}

- (void)loadRequestWithResultBlock:(KKHttpConnectionBlock)resultBlock
{
    self.httpResultBlock = resultBlock;
    [[KKBaseHttpQueue sharedRequestQueue] enqueueOperation:self];
}


#pragma mark - Block 回调结果

- (void)requestFailed:(NSError *)error
{
    self.state = KKHTTPOprerationState_Finished;
    self.responseData = nil;
    [self setHttpResultWithSuccess:nil error:error isSuccessed:NO];
}

- (void)responseReceived
{
    [self setHttpResultWithSuccess:self.responseData error:nil isSuccessed:YES];
}

- (void)setHttpResultWithSuccess:(NSData *)data error:(NSError *)error isSuccessed:(BOOL)isSuccessed
{
    if (self.httpResultBlock) {
        if (self.shouldCompleteOnMainThread) {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                self.httpResultBlock(isSuccessed,data,error);
            });
        } else {
            self.httpResultBlock(isSuccessed,data,error);
        }
    }
    self.connection = nil;
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    self.state = KKHTTPOprerationState_Finished;
    [self requestFailed:error];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.responseData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if([self isCancelled])
        return;
    
    self.state = KKHTTPOprerationState_Finished;
    
    [self responseReceived];
}



@end
