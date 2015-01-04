//
//  QNFormUpload.m
//  QiniuSDK
//
//  Created by bailong on 15/1/4.
//  Copyright (c) 2015年 Qiniu. All rights reserved.
//

#import "QNFormUpload.h"
#import "QNUploadManager.h"
#import "QNUrlSafeBase64.h"
#import "QNConfig.h"
#import "QNResponseInfo.h"
#import "QNHttpManager.h"
#import "QNUploadOption+Private.h"
#import "QNRecorderDelegate.h"
#import "QNCrc32.h"

@interface QNFormUpload ()

@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) QNHttpManager *httpManager;
@property (nonatomic) int retryTimes;
@property (nonatomic, strong) NSString *key;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) QNUploadOption *option;
@property (nonatomic, strong) QNUpCompletionHandler complete;


@end

@implementation QNFormUpload

- (instancetype)initWithData:(NSData *)data
                     withKey:(NSString *)key
                   withToken:(NSString *)token
       withCompletionHandler:(QNUpCompletionHandler)block
                  withOption:(QNUploadOption *)option
             withHttpManager:(QNHttpManager *)http {
	if (self = [super init]) {
		_data = data;
		_key = key;
		_token = token;
		_option = option;
		_complete = block;
		_httpManager = http;
	}
	return self;
}

- (void)put {
	NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
	NSString *fileName = _key;
	if (_key) {
		parameters[@"key"] = _key;
	}
	else {
		fileName = @"?";
	}

	parameters[@"token"] = _token;

	if (_option && _option.params) {
		[parameters addEntriesFromDictionary:_option.params];
	}

	NSString *mimeType = @"application/octet-stream";

	if (_option && _option.mimeType) {
		mimeType = _option.mimeType;
	}

	if (_option && _option.checkCrc) {
		parameters[@"crc32"] = [NSString stringWithFormat:@"%u", (unsigned int)[QNCrc32 data:_data]];
	}

	QNInternalProgressBlock p = nil;

	if (_option && _option.progressHandler) {
		p = ^(long long totalBytesWritten, long long totalBytesExpectedToWrite) {
			float percent = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
			if (percent > 0.95) {
				percent = 0.95;
			}
			_option.progressHandler(_key, percent);
		};
	}

	QNCompleteBlock complete = ^(QNResponseInfo *info, NSDictionary *resp)
	{
		if (info.isOK && p) {
			_option.progressHandler(_key, 1.0);
		}
		if (info.isOK || !info.couldRetry) {
			_complete(info, _key, resp);
			return;
		}
		NSString *nextHost = kQNUpHost;
		if (info.isConnectionBroken) {
			nextHost = kQNUpHostBackup;
		}

		QNCompleteBlock retriedComplete = ^(QNResponseInfo *info, NSDictionary *resp) {
			if (info.isOK && p) {
				_option.progressHandler(_key, 1.0);
			}
			_complete(info, _key, resp);
		};

		[_httpManager multipartPost:[NSString stringWithFormat:@"http://%@", nextHost]
		                   withData:_data
		                 withParams:parameters
		               withFileName:fileName
		               withMimeType:mimeType
		          withCompleteBlock:retriedComplete
		          withProgressBlock:p
		            withCancelBlock:nil];
	};

	[_httpManager multipartPost:[NSString stringWithFormat:@"http://%@", kQNUpHost]
	                   withData:_data
	                 withParams:parameters
	               withFileName:fileName
	               withMimeType:mimeType
	          withCompleteBlock:complete
	          withProgressBlock:p
	            withCancelBlock:nil];
}

@end