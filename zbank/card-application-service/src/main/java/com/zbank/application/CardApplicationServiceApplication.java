package com.zbank.application;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.openfeign.EnableFeignClients;

@SpringBootApplication
@EnableFeignClients
public class CardApplicationServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(CardApplicationServiceApplication.class, args);
    }
}
