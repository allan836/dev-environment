package nl.dtg.kv.task.distributed.impl;

import com.hazelcast.cluster.Member;
import com.hazelcast.config.Config;
import com.hazelcast.config.XmlConfigBuilder;
import com.hazelcast.core.Hazelcast;
import com.hazelcast.core.HazelcastInstance;
import nl.dtg.kv.cache.CacheType;
import nl.dtg.kv.endpoint.exception.ServiceException;
import nl.dtg.kv.model.BuildVersion;
import nl.dtg.kv.status.ApplicationStatusManager;
import nl.dtg.kv.status.model.BuildSnapshot;
import nl.dtg.kv.status.model.HazelcastServerSnapshot;
import nl.dtg.kv.status.model.MemorySnapshot;
import nl.dtg.kv.task.distributed.MapChangedListener;
import nl.dtg.kv.task.distributed.model.HeartBeat;
import nl.dtg.kv.task.distributed.model.ServerSnapshot;
import nl.dtg.kv.util.DateUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.InputStream;
import java.time.ZonedDateTime;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

public class HazelCastClusterManager extends AbstractClusterManager {

    private static final Logger LOGGER = LoggerFactory.getLogger(HazelCastClusterManager.class.getName());

    protected HazelcastInstance instance;
    private final int maxIdleTimeInSeconds;
    private final long waitForLockConfirmation;
    private final BuildSnapshot buildSnapshot;
    private final HazelcastServerSnapshot hazelcastServerSnapshot;

    public HazelCastClusterManager(final String instanceName,
                                   final int maxIdleTimeInSeconds,
                                   final long waitForLockConfirmation,
                                   final BuildVersion buildVersion) {
        super();
        this.maxIdleTimeInSeconds = maxIdleTimeInSeconds;
        this.waitForLockConfirmation = waitForLockConfirmation;

        /* local setup start */
        System.setProperty("hazelcast.ignoreXxeProtectionFailures", "true");
        try (InputStream configStream = getClass().getClassLoader().getResourceAsStream("hazelcast.xml")) {
            Config config;
            if (configStream != null) {
                config = new XmlConfigBuilder(configStream).build();
                LOGGER.info("Loaded Hazelcast configuration from resources/hazelcast.xml");
            } else {
                config = new Config();
                LOGGER.warn("hazelcast.xml not found in resources, using default config");
            }

            // Override the instance name from XML
            if (instanceName != null && !instanceName.isEmpty()) {
                config.setInstanceName(instanceName);
            }
            // Create Hazelcast instance
            this.instance = Hazelcast.newHazelcastInstance(config);

        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize Hazelcast instance: " + e.getMessage(), e);
        }
        /* local setup end */


        /* Initialize */
        this.instance.getMap(DISTRIBUTED_TASK_MAP);
        this.instance.getMap(MEMORY_STATUS_MAP);
        this.instance.getMap(MIGRATION_TASK_MAP);

        this.instance.getMap(VERIFIED_OTP_MAP);
        this.instance.getMap(PENDING_OTP_MAP);
        this.instance.getMap(LOCKOUT_OTP_MAP);

        this.instance.getMap(LOCATION_AI_SUMMARY_MAP);

        this.buildSnapshot = new BuildSnapshot(
                buildVersion.getMavenVersion(),
                buildVersion.getMavenBuildTimestamp(),
                buildVersion.getGitRevision(),
                buildVersion.getGitBranch(),
                buildVersion.getGitTag()
        );
        this.hazelcastServerSnapshot = new HazelcastServerSnapshot(
                getServerId(),
                instanceName,
                instance.getLocalEndpoint().getSocketAddress().toString()
        );
    }

    public void shutDown() {
        if (instance != null) {
            instance.shutdown();
        }
    }

    public HazelcastInstance getInstance() {
        return instance;
    }

    @Override
    public void register() throws ServiceException {
        try {
            instance.getMap(HEART_BEAT_MAP).put(getServerId(), System.currentTimeMillis());
        } catch (Exception ex) {
            throw new ServiceException("Unable to register this server: " + ex.getMessage(), ex);
        }
    }

    @Override
    public void unRegister() throws ServiceException {
        try {
            instance.getMap(HEART_BEAT_MAP).remove(getServerId());
        } catch (Exception ex) {
            throw new ServiceException("Unable to un-register this server: " + ex.getMessage(), ex);
        }
    }

    @Override
    public void keepAlive() throws ServiceException {
        try {
            instance.getMap(HEART_BEAT_MAP).put(getServerId(), System.currentTimeMillis());
        } catch (Exception ex) {
            throw new ServiceException("Unable to keep-alive this server: " + ex.getMessage(), ex);
        }
    }

    @Override
    public <T> String requestLockOnTask(String mapType, T taskId) throws ServiceException {
        try {
            LOGGER.debug("Requesting lock on task-> " + taskId + " for map type-> " + mapType + " getMap(mapType).get(taskId) -> "+instance.getMap(mapType).get(taskId));
            String previous = (String) instance.getMap(mapType).putIfAbsent(taskId, getServerId(), maxIdleTimeInSeconds, TimeUnit.SECONDS);
            if (previous == null) {
                return getServerId();
            }
            return null;
        } catch (Exception ex) {
            throw new ServiceException("Unable to request lock: " + ex.getMessage(), ex);
        }
    }

    @Override
    public <T> void addForceExpiry(String mapType, T taskId) {
        instance.getMap(mapType).setTtl(taskId, maxIdleTimeInSeconds, TimeUnit.SECONDS);
    }

    @Override
    public <T> void releaseLockOnTask(String mapType, T taskId) throws ServiceException {
        try {
            instance.getMap(mapType).remove(taskId);
        } catch (Exception ex) {
            throw new ServiceException("Unable to release lock: " + ex.getMessage(), ex);
        }
    }

    @Override
    public boolean isTaskLocked(long taskId) {
        try {
            return instance.getMap(DISTRIBUTED_TASK_MAP).get(taskId) != null;
        } catch (Exception ex) {
            ApplicationStatusManager.getInstance().addError(new ServiceException("Unable to determine if the task is locked: " + ex.getMessage(), ex), true);
        }
        return false;
    }

    @Override
    public List<HeartBeat> getHeartBeats() throws ServiceException {
        try {
            List<HeartBeat> heartBeats = new ArrayList<>();
            Map<String, Long> map = instance.getMap(HEART_BEAT_MAP);
            heartBeats.addAll(
                    map.entrySet().stream().map(
                            entry -> new HeartBeat(entry.getKey(), entry.getValue())).collect(Collectors.toList()
                    )
            );
            return heartBeats;
        } catch (Exception ex) {
            throw new ServiceException("Unable to get heart-beats: " + ex.getMessage(), ex);
        }
    }

    @Override
    public void purgeLockedDistributedTasks() throws ServiceException {
        try {
            getHeartBeats().stream().filter(heartBeat -> !heartBeat.consideredAlive(maxIdleTimeInSeconds))
                    .forEach(heartBeat -> {
                        Map<Long, String> map = instance.getMap(DISTRIBUTED_TASK_MAP);
                        List<Long> toBeRemovedLocks = map.entrySet().stream()
                                .filter(entry -> heartBeat.getServerId().equals(map.get(entry.getKey())))
                                .map(Map.Entry::getKey).collect(Collectors.toList());
                        if (!toBeRemovedLocks.isEmpty()) {
                            ApplicationStatusManager.getInstance().addError(new ServiceException("Removing tasks: " + toBeRemovedLocks.toString() + " owned by crashed server [" + heartBeat.getServerId() + "]"), true);
                            toBeRemovedLocks.forEach(l -> instance.getMap(DISTRIBUTED_TASK_MAP).remove(l));
                        }
                        ApplicationStatusManager.getInstance().addError(new ServiceException("Removing serverId heart-beat: " + heartBeat.getServerId() + " since it was not stopped correctly."), true);
                        instance.getMap(HEART_BEAT_MAP).remove(heartBeat.getServerId());
                    });
        } catch (Exception ex) {
            throw new ServiceException("Unable to purge distributed tasks: " + ex.getMessage(), ex);
        }
    }

    @Override
    public String addListener(MapChangedListener mapChangedListener) throws ServiceException {
        try {
            return instance.getMap(CACHE_UPDATE_MAP).addEntryListener(mapChangedListener, true).toString();
        } catch (Exception ex) {
            throw new ServiceException("Unable to add a map listener.", ex);
        }
    }

    @Override
    public void removeListener(String id) {
        if (instance != null && id != null) {
            instance.getMap(CACHE_UPDATE_MAP).removeEntryListener(UUID.fromString(id));
        }
    }

    @Override
    public void sendCacheUpdateEvent(CacheType cacheType) throws ServiceException {
        if (instance != null && cacheType != null) {
            instance.getMap(CACHE_UPDATE_MAP).put(cacheType.name(), DateUtils.toIsoZonedDateTimeString(ZonedDateTime.now()));
        }
    }

    @Override
    public String getLastCacheUpdate(CacheType cacheType) throws ServiceException {
        try {
            return (String) instance.getMap(CACHE_UPDATE_MAP).get(cacheType.name());
        } catch (Exception ex) {
            throw new ServiceException("Unable to get cache details for: " + (cacheType != null ? cacheType.name() : "null") + " : " + ex.getMessage(), ex);
        }
    }

    @Override
    public void sendMemoryUpdateEvent(MemorySnapshot memorySnapshot) throws ServiceException {
        if (instance != null && memorySnapshot != null) {
            instance.getMap(MEMORY_STATUS_MAP).put(instance.getCluster().getLocalMember().getUuid(),
                    new ServerSnapshot(memorySnapshot, buildSnapshot, hazelcastServerSnapshot));
        }

        if (instance != null) {
            Set<Object> activeMembers = instance.getCluster().getMembers().stream()
                    .map(Member::getUuid).collect(Collectors.toSet());
            List<Object> removedMembers = instance.getMap(MEMORY_STATUS_MAP).keySet().stream()
                    .filter(memberUuid -> !activeMembers.contains(memberUuid)).collect(Collectors.toList());
            removedMembers.forEach(member -> instance.getMap(MEMORY_STATUS_MAP).remove(member));
        }
    }

    @Override
    public List<ServerSnapshot> getMemorySnapshot() throws ServiceException {
        try {
            return instance.getMap(MEMORY_STATUS_MAP).values().stream().map(object -> (ServerSnapshot) object).collect(Collectors.toList());
        } catch (Exception ex) {
            throw new ServiceException("Unable to get Memory snapshot :" + ex.getMessage(), ex);
        }
    }
}
