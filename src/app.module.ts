import { Module } from '@nestjs/common';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { UsersModule } from './users/users.module';

@Module({
    imports: [UsersModule],
    providers: [
        {
            provide: 'PG_CONNECTION',
            useFactory: (): any => {
                return new Pool({
                    host: 'localhost',
                    port: 5432,
                    user: 'postgres',
                    password: 'admin',
                    database: 'test',
                });
            },
        },
        {
            provide: 'REDIS_CLIENT',
            useFactory: (): any => {
                return new Redis({
                    host: 'localhost',
                    port: 6379,
                });
            },
        },
    ],
    exports: ['PG_CONNECTION', 'REDIS_CLIENT'],
})
export class AppModule {}
