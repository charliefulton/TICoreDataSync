//
//  TICDSFileManagerBasedDocumentSyncManager.m
//  ShoppingListMac
//
//  Created by Tim Isted on 22/04/2011.
//  Copyright 2011 Tim Isted. All rights reserved.
//

#import "TICoreDataSync.h"

@implementation TICDSFileManagerBasedDocumentSyncManager

#pragma mark -
#pragma mark Automatic Change Detection
- (void)enableAutomaticSynchronizationAfterChangesDetectedFromOtherClients
{
    if( _directoryWatcher ) {
        return;
    }
    
    _directoryWatcher = [[TIKQDirectoryWatcher alloc] init];
    
    NSError *anyError = nil;
    BOOL success = [_directoryWatcher watchDirectory:[self thisDocumentSyncChangesDirectoryPath] error:&anyError];
    
    if( !success ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to watch document's SyncChanges directory");
        return;
    }
    
    if( _watchedClientDirectoryIdentifiers ) {
        [_watchedClientDirectoryIdentifiers release], _watchedClientDirectoryIdentifiers = nil;
    }
    
    NSArray *clientIdentfiers = [[self fileManager] contentsOfDirectoryAtPath:[self thisDocumentSyncChangesDirectoryPath] error:&anyError];
    if( !clientIdentfiers ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to get contents of document's SyncChanges directory: %@", anyError);
        return;
    }
    
    _watchedClientDirectoryIdentifiers = [[NSMutableArray alloc] initWithCapacity:[clientIdentfiers count]];
    NSString *eachPath = nil;
    for( NSString *eachIdentifier in clientIdentfiers ) {
        if( [[eachIdentifier substringToIndex:1] isEqualToString:@"."] || [eachIdentifier isEqualToString:[self clientIdentifier]] ) {
            continue;
        }
        
        [_watchedClientDirectoryIdentifiers addObject:eachIdentifier];
        
        eachPath = [[self thisDocumentSyncChangesDirectoryPath] stringByAppendingPathComponent:eachIdentifier];
        
        success = [_directoryWatcher watchDirectory:eachPath error:&anyError];
        if( !success ) {
            TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to watch %@ client's SyncChanges directory");
            return;
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(directoryContentsDidChange:) name:kTIKQDirectoryWatcherObservedDirectoryActivityNotification object:_directoryWatcher];
    
    success = [_directoryWatcher scheduleWatcherOnMainRunLoop:&anyError];
    if( !success ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to schedule directory watcher on the run loop");
        return;
    }
}

- (void)directoryContentsDidChange:(NSNotification *)aNotification
{
    NSString *aPath = [[aNotification userInfo] valueForKey:kTIKQExpandedDirectory];
    
    if( ![[aPath lastPathComponent] isEqualToString:TICDSSyncChangesDirectoryName] ) {
        // another client has synchronized
        [self initiateSynchronization];
        return;
    }
    
    NSError *anyError = nil;
    // otherwise, go through each identifier to add another watcher
    NSArray *clientIdentfiers = [[self fileManager] contentsOfDirectoryAtPath:[self thisDocumentSyncChangesDirectoryPath] error:&anyError];
    if( !clientIdentfiers ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to get contents of document's SyncChanges directory: %@", anyError);
        return;
    }
    
    NSString *eachPath = nil;
    for( NSString *eachIdentifier in clientIdentfiers ) {
        if( [[eachIdentifier substringToIndex:1] isEqualToString:@"."] || [eachIdentifier isEqualToString:[self clientIdentifier]] ) {
            continue;
        }
        
        if( [[self watchedClientDirectoryIdentifiers] containsObject:eachIdentifier] ) {
            continue;
        }
        
        TICDSLog(TICDSLogVerbosityEveryStep, @"Not yet watching %@, so adding a directory watcher", eachIdentifier);
        
        eachPath = [[self thisDocumentSyncChangesDirectoryPath] stringByAppendingPathComponent:eachIdentifier];
        
        BOOL success = [[self directoryWatcher] watchDirectory:eachPath error:&anyError];
        if( !success ) {
            TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to watch directory");
        } else {
            [[self watchedClientDirectoryIdentifiers] addObject:eachIdentifier];
        }
    }
}

#pragma mark -
#pragma mark Registration
- (void)registerWithDelegate:(id<TICDSDocumentSyncManagerDelegate>)aDelegate appSyncManager:(TICDSApplicationSyncManager *)anAppSyncManager managedObjectContext:(TICDSSynchronizedManagedObjectContext *)aContext documentIdentifier:(NSString *)aDocumentIdentifier description:(NSString *)aDocumentDescription userInfo:(NSDictionary *)someUserInfo
{
    if( [anAppSyncManager isKindOfClass:[TICDSFileManagerBasedApplicationSyncManager class]] ) {
        [self setApplicationDirectoryPath:[(TICDSFileManagerBasedApplicationSyncManager *)anAppSyncManager applicationDirectoryPath]];
    }
    
    [super registerWithDelegate:aDelegate appSyncManager:anAppSyncManager managedObjectContext:aContext documentIdentifier:aDocumentIdentifier description:aDocumentDescription userInfo:someUserInfo];
}

#pragma mark -
#pragma mark Operation Classes
- (TICDSDocumentRegistrationOperation *)documentRegistrationOperation
{
    TICDSFileManagerBasedDocumentRegistrationOperation *operation = [[TICDSFileManagerBasedDocumentRegistrationOperation alloc] initWithDelegate:self];
    
    [operation setDocumentsDirectoryPath:[self documentsDirectoryPath]];
    [operation setDeletedDocumentsThisDocumentIdentifierPlistPath:[self deletedDocumentsThisDocumentIdentifierPlistPath]];
    [operation setThisDocumentDirectoryPath:[self thisDocumentDirectoryPath]];
    [operation setThisDocumentSyncChangesThisClientDirectoryPath:[self thisDocumentSyncChangesThisClientDirectoryPath]];
    [operation setThisDocumentSyncCommandsThisClientDirectoryPath:[self thisDocumentSyncCommandsThisClientDirectoryPath]];
    
    return [operation autorelease];
}

- (TICDSWholeStoreUploadOperation *)wholeStoreUploadOperation
{
    TICDSFileManagerBasedWholeStoreUploadOperation *operation = [[TICDSFileManagerBasedWholeStoreUploadOperation alloc] initWithDelegate:self];
    
    [operation setThisDocumentTemporaryWholeStoreThisClientDirectoryPath:[self thisDocumentTemporaryWholeStoreThisClientDirectoryPath]];
    [operation setThisDocumentTemporaryWholeStoreThisClientDirectoryWholeStoreFilePath:[self thisDocumentTemporaryWholeStoreFilePath]];
    [operation setThisDocumentTemporaryWholeStoreThisClientDirectoryAppliedSyncChangeSetsFilePath:[self thisDocumentTemporaryAppliedSyncChangeSetsFilePath]];
    [operation setThisDocumentWholeStoreThisClientDirectoryPath:[self thisDocumentWholeStoreThisClientDirectoryPath]];
    
    return [operation autorelease];
}

- (TICDSWholeStoreDownloadOperation *)wholeStoreDownloadOperation
{
    TICDSFileManagerBasedWholeStoreDownloadOperation *operation = [[TICDSFileManagerBasedWholeStoreDownloadOperation alloc] initWithDelegate:self];
    
    [operation setThisDocumentWholeStoreDirectoryPath:[self thisDocumentWholeStoreDirectoryPath]];
    
    return [operation autorelease];
}

- (TICDSSynchronizationOperation *)synchronizationOperation
{
    TICDSFileManagerBasedSynchronizationOperation *operation = [[TICDSFileManagerBasedSynchronizationOperation alloc] initWithDelegate:self];
    
    [operation setThisDocumentSyncChangesDirectoryPath:[self thisDocumentSyncChangesDirectoryPath]];
    [operation setThisDocumentSyncChangesThisClientDirectoryPath:[self thisDocumentSyncChangesThisClientDirectoryPath]];
    [operation setThisDocumentRecentSyncsThisClientFilePath:[self thisDocumentRecentSyncsThisClientFilePath]];
    
    return [operation autorelease];
}

- (TICDSVacuumOperation *)vacuumOperation
{
    TICDSFileManagerBasedVacuumOperation *operation = [[TICDSFileManagerBasedVacuumOperation alloc] initWithDelegate:self];
    
    [operation setThisDocumentWholeStoreDirectoryPath:[self thisDocumentWholeStoreDirectoryPath]];
    [operation setThisDocumentRecentSyncsDirectoryPath:[self thisDocumentRecentSyncsDirectoryPath]];
    [operation setThisDocumentSyncChangesThisClientDirectoryPath:[self thisDocumentSyncChangesThisClientDirectoryPath]];
    
    return [operation autorelease];
}

- (TICDSListOfDocumentRegisteredClientsOperation *)listOfDocumentRegisteredClientsOperation
{
    TICDSFileManagerBasedListOfDocumentRegisteredClientsOperation *operation = [[TICDSFileManagerBasedListOfDocumentRegisteredClientsOperation alloc] initWithDelegate:self];
    
    [operation setThisDocumentSyncChangesDirectoryPath:[self thisDocumentSyncChangesDirectoryPath]];
    [operation setClientDevicesDirectoryPath:[self clientDevicesDirectoryPath]];
    [operation setThisDocumentRecentSyncsDirectoryPath:[self thisDocumentRecentSyncsDirectoryPath]];
    [operation setThisDocumentWholeStoreDirectoryPath:[self thisDocumentWholeStoreDirectoryPath]];
    
    return [operation autorelease];
}

#pragma mark -
#pragma mark Paths
- (NSString *)clientDevicesDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToClientDevicesDirectory]];
}

- (NSString *)deletedDocumentsThisDocumentIdentifierPlistPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToDeletedDocumentsThisDocumentIdentifierPlistFile]];
}

- (NSString *)documentsDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToDocumentsDirectory]];
}

- (NSString *)thisDocumentDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentDirectory]];
}

- (NSString *)thisDocumentSyncChangesDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentSyncChangesDirectory]];
}

- (NSString *)thisDocumentSyncChangesThisClientDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentSyncChangesThisClientDirectory]];
}

- (NSString *)thisDocumentSyncCommandsDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentSyncCommandsDirectory]];
}

- (NSString *)thisDocumentSyncCommandsThisClientDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentSyncCommandsThisClientDirectory]];
}

- (NSString *)thisDocumentTemporaryWholeStoreThisClientDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentTemporaryWholeStoreThisClientDirectory]];
}

- (NSString *)thisDocumentTemporaryWholeStoreFilePath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentTemporaryWholeStoreThisClientDirectoryWholeStoreFile]];
}

- (NSString *)thisDocumentTemporaryAppliedSyncChangeSetsFilePath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentTemporaryWholeStoreThisClientDirectoryAppliedSyncChangeSetsFile]];
}

- (NSString *)thisDocumentWholeStoreDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentWholeStoreDirectory]];
}

- (NSString *)thisDocumentWholeStoreThisClientDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentWholeStoreThisClientDirectory]];
}

- (NSString *)thisDocumentWholeStoreFilePath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentWholeStoreThisClientDirectoryWholeStoreFile]];
}

- (NSString *)thisDocumentAppliedSyncChangeSetsFilePath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentWholeStoreThisClientDirectoryAppliedSyncChangeSetsFile]];
}

- (NSString *)thisDocumentRecentSyncsDirectoryPath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentRecentSyncsDirectory]];
}

- (NSString *)thisDocumentRecentSyncsThisClientFilePath
{
    return [[self applicationDirectoryPath] stringByAppendingPathComponent:[self relativePathToThisDocumentRecentSyncsDirectoryThisClientFile]];
}

#pragma mark -
#pragma mark Initialization and Deallocation
- (void)dealloc
{
    [_applicationDirectoryPath release], _applicationDirectoryPath = nil;
    [_directoryWatcher release], _directoryWatcher = nil;
    [_watchedClientDirectoryIdentifiers release], _watchedClientDirectoryIdentifiers = nil;

    [super dealloc];
}

#pragma mark -
#pragma mark Properties
@synthesize applicationDirectoryPath = _applicationDirectoryPath;
@synthesize directoryWatcher = _directoryWatcher;
@synthesize watchedClientDirectoryIdentifiers = _watchedClientDirectoryIdentifiers;

@end
