import { Injectable, Inject } from '@nestjs/common';
import { Pool } from 'pg';
import Redis from 'ioredis';

@Injectable()
export class UsersService {
    constructor(
        @Inject('PG_CONNECTION') private readonly pg: Pool,
        @Inject('REDIS_CLIENT') private readonly redis: Redis,
    ) {}

    async findById(id: number) {
        const cacheKey = `user:${id}`;

        const start = Date.now();

        // 🔎 1. tenta cache
        const cached = await this.redis.get(cacheKey);
        if (cached) {
            return {
                source: 'redis',
                timeMs: Date.now() - start,
                data: JSON.parse(cached),
            };
        }

        // 🐘 2. busca no postgres
        const result = await this.pg.query(
            'SELECT id, nome, email FROM users WHERE id = $1',
            [id],
        );

        const user = result.rows[0];

        if (!user) return null;

        // 💾 3. salva no cache
        await this.redis.set(cacheKey, JSON.stringify(user), 'EX', 60);

        return {
            source: 'postgres',
            timeMs: Date.now() - start,
            data: user,
        };
    }
}
