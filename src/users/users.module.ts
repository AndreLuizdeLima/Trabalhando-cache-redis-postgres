import { Module } from '@nestjs/common';
import { Pool } from 'pg';
import Redis from 'ioredis';

import { UsersService } from './users.service';
import { UsersController } from './users.controller';

@Module({
    controllers: [UsersController],
    providers: [
        UsersService,

        // 🐘 PostgreSQL
        {
            provide: 'PG_CONNECTION',
            useFactory: () => {
                return new Pool({
                    host: 'localhost',
                    port: 5432,
                    user: 'postgres',
                    password: 'admin',
                    database: 'teste',
                });
            },
        },

        // 🔴 Redis
        {
            provide: 'REDIS_CLIENT',
            useFactory: () => {
                return new Redis({
                    host: 'localhost',
                    port: 6379,
                    password: 'admin',
                });
            },
        },
    ],
})
export class UsersModule {}
