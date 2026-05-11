import { Injectable, Inject } from '@nestjs/common';
import Redis from 'ioredis';
import { Pool, QueryResult } from 'pg';

interface User {
    id: number;
    nome: string;
    email: string;
}

interface UserReport {
    id: number;
    nome: string;
    email: string;
    totalCourses: number;
    averageScore: number | null;
    activeCourses: number;
    studentSummary: string;
    courses: string;
}

export interface UserResponse {
    source: 'redis' | 'postgres';
    timeMs: number;
    data: User | UserReport | null;
}

@Injectable()
export class UsersService {
    private pg: Pool;
    private redis: Redis;

    constructor(
        @Inject('PG_CONNECTION') pg: Pool,
        @Inject('REDIS_CLIENT') redis: Redis,
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
                const user = JSON.parse(cached) as User;
                return {
                    source: 'redis',
                    timeMs: Date.now() - start,
                    data: user,
                };
            }

            // 🐘 2. busca no postgres
            const user = await this.findUserInPostgres(id);

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

    async findByIdWithoutCache(id: number): Promise<UserResponse | null> {
        const start = Date.now();

        try {
            const user = await this.findUserInPostgres(id);

            return {
                source: 'postgres',
                timeMs: Date.now() - start,
                data: user ?? null,
            };
        } catch (error) {
            console.error('Database error:', error);
            return null;
        }
    }

    async findReportById(id: number): Promise<UserResponse | null> {
        const cacheKey = `user:${id}:report`;
        const start = Date.now();

        try {
            const cached: string | null = await this.redis.get(cacheKey);
            if (cached) {
                const report = JSON.parse(cached) as UserReport;
                return {
                    source: 'redis',
                    timeMs: Date.now() - start,
                    data: report,
                };
            }

            const report = await this.findUserReportInPostgres(id);

            if (!report) {
                return {
                    source: 'postgres',
                    timeMs: Date.now() - start,
                    data: null,
                };
            }

            try {
                await this.redis.set(
                    cacheKey,
                    JSON.stringify(report),
                    'EX',
                    60,
                );
            } catch (cacheError) {
                console.warn('Cache write error:', cacheError);
            }

            return {
                source: 'postgres',
                timeMs: Date.now() - start,
                data: report,
            };
        } catch (error) {
            console.error('Database error:', error);
            return null;
        }
    }

    async findReportByIdWithoutCache(id: number): Promise<UserResponse | null> {
        const start = Date.now();

        try {
            const report = await this.findUserReportInPostgres(id);

            return {
                source: 'postgres',
                timeMs: Date.now() - start,
                data: report ?? null,
            };
        } catch (error) {
            console.error('Database error:', error);
            return null;
        }
    }

    private async findUserInPostgres(id: number): Promise<User | undefined> {
        const result: QueryResult<User> = await this.pg.query(
            'SELECT id, nome, email FROM users WHERE id = $1',
            [id],
        );

        return result.rows[0];
    }

    private async findUserReportInPostgres(
        id: number,
    ): Promise<UserReport | undefined> {
        const result: QueryResult<UserReport> = await this.pg.query(
            `
            SELECT
                u.id,
                u.nome,
                u.email,
                (
                    SELECT count(*)::int
                    FROM student_courses sc_total
                    WHERE sc_total.user_id = u.id
                ) AS "totalCourses",
                round(avg(sc.score), 2)::float AS "averageScore",
                count(*) FILTER (WHERE sc.status = 'active')::int AS "activeCourses",
                concat(
                    u.nome,
                    ' <',
                    u.email,
                    '> tem ',
                    count(sc.id),
                    ' matriculas. Ultimos cursos: ',
                    coalesce(
                        string_agg(
                            sc.course_name || ' (' || sc.status || ')',
                            ', '
                            ORDER BY sc.created_at DESC
                        ),
                        'sem matriculas'
                    )
                ) AS "studentSummary",
                coalesce(
                    string_agg(
                        sc.course_name || ':' || sc.status || ':' || sc.score,
                        ' | '
                        ORDER BY sc.created_at DESC
                    ),
                    ''
                ) AS courses
            FROM users u
            LEFT JOIN student_courses sc ON sc.user_id = u.id
            WHERE u.id = $1
            GROUP BY u.id, u.nome, u.email
            `,
            [id],
        );

        return result.rows[0];
    }
}
