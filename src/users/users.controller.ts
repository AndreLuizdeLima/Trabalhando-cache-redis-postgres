import { Controller, Get, Param, ParseIntPipe } from '@nestjs/common';
import { UsersService, UserResponse } from './users.service';

@Controller('users')
export class UsersController {
    constructor(private readonly usersService: UsersService) {}

    @Get(':id/report/no-cache')
    async getUserReportWithoutCache(
        @Param('id', ParseIntPipe) id: number,
    ): Promise<UserResponse | null> {
        return this.usersService.findReportByIdWithoutCache(id);
    }

    @Get(':id/report')
    async getUserReport(
        @Param('id', ParseIntPipe) id: number,
    ): Promise<UserResponse | null> {
        return this.usersService.findReportById(id);
    }

    @Get(':id/no-cache')
    async getUserWithoutCache(
        @Param('id', ParseIntPipe) id: number,
    ): Promise<UserResponse | null> {
        return this.usersService.findByIdWithoutCache(id);
    }

    @Get(':id')
    async getUser(
        @Param('id', ParseIntPipe) id: number,
    ): Promise<UserResponse | null> {
        return this.usersService.findById(id);
    }
}
