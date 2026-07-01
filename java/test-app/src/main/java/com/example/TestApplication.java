package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.RuntimeMXBean;
import java.util.LinkedHashMap;
import java.util.Map;

@SpringBootApplication
@RestController
public class TestApplication {

    public static void main(String[] args) {
        SpringApplication.run(TestApplication.class, args);
    }

    @GetMapping("/api/info")
    public Map<String, Object> info() {
        RuntimeMXBean runtime = ManagementFactory.getRuntimeMXBean();
        MemoryMXBean memory = ManagementFactory.getMemoryMXBean();
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("app", "test-app");
        map.put("status", "running");
        map.put("java", runtime.getVmVersion());
        map.put("jvm", runtime.getVmName());
        map.put("uptime", runtime.getUptime());
        map.put("heapMax", memory.getHeapMemoryUsage().getMax() / 1024 / 1024 + " MB");
        return map;
    }
}
