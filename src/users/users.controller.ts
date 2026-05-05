import { Controller, Get, Param, ParseIntPipe } from '@nestjs/common';
import { UsersService, UserResponse } from './users.service';

@Controller('users')
export class UsersController {
    constructor(private readonly usersService: UsersService) {}

    @Get(':id')
    async getUser(
        @Param('id', ParseIntPipe) id: number,
    ): Promise<UserResponse | null> {
        return this.usersService.findById(id);
    }
}
