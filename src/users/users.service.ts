import { Injectable, Inject } from '@nestjs/common';

interface User {
    id: number;
    nome: string;
    email: string;
}

export interface UserResponse {
    source: 'redis' | 'postgres';
    timeMs: number;
    data: User | null;
}

@Injectable()
export class UsersService {
    private pg: any;
    private redis: any;

    constructor(
        @Inject('PG_CONNECTION') pg: any,
        @Inject('REDIS_CLIENT') redis: any,
    ) {
        this.pg = pg;
        this.redis = redis;
    }

    async findById(id: number): Promise<UserResponse | null> {
        const cacheKey = `user:${id}`;
        const start = Date.now();

        try {
            // 🔎 1. tenta cache
            const cached: string | null = await this.redis.get(cacheKey);
            if (cached) {
                const user: User = JSON.parse(cached);
                return {
                    source: 'redis',
                    timeMs: Date.now() - start,
                    data: user,
                };
            }

            // 🐘 2. busca no postgres
            const result: any = await this.pg.query(
                'SELECT id, nome, email FROM users WHERE id = $1',
                [id],
            );

            const user: User | undefined = result?.rows?.[0];

            if (!user) {
                return {
                    source: 'postgres',
                    timeMs: Date.now() - start,
                    data: null,
                };
            }

            // 💾 3. salva no cache
            try {
                await this.redis.set(cacheKey, JSON.stringify(user), 'EX', 60);
            } catch (cacheError) {
                console.warn('Cache write error:', cacheError);
            }

            return {
                source: 'postgres',
                timeMs: Date.now() - start,
                data: user,
            };
        } catch (error) {
            console.error('Database error:', error);
            return null;
        }
    }
}
