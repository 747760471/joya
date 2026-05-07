; ModuleID = 'joya_module'
source_filename = "joya_module"
target triple = "x86_64-pc-windows-msvc"

%Point = type { i64, i64 }

@fmt_int_nl = private unnamed_addr constant [6 x i8] c"%lld\0A\00", align 1
@fmt_int_nl.1 = private unnamed_addr constant [6 x i8] c"%lld\0A\00", align 1
@fmt_int_nl.2 = private unnamed_addr constant [6 x i8] c"%lld\0A\00", align 1
@fmt_int_nl.3 = private unnamed_addr constant [6 x i8] c"%lld\0A\00", align 1
@fmt_int_nl.4 = private unnamed_addr constant [6 x i8] c"%lld\0A\00", align 1

declare i32 @printf(ptr, ...)

declare ptr @malloc(i64)

define void @Point_Point(ptr %0, i64 %1, i64 %2) {
entry:
  %this = alloca ptr, align 8
  store ptr %0, ptr %this, align 8
  %x = alloca i64, align 8
  store i64 %1, ptr %x, align 4
  %y = alloca i64, align 8
  store i64 %2, ptr %y, align 4
  %x1 = load i64, ptr %x, align 4
  %this_val = load ptr, ptr %this, align 8
  %field_ptr = getelementptr %Point, ptr %this_val, i32 0, i32 0
  store i64 %x1, ptr %field_ptr, align 4
  %y2 = load i64, ptr %y, align 4
  %this_val3 = load ptr, ptr %this, align 8
  %field_ptr4 = getelementptr %Point, ptr %this_val3, i32 0, i32 1
  store i64 %y2, ptr %field_ptr4, align 4
  ret void
}

define i64 @Point_getX(ptr %0) {
entry:
  %this = alloca ptr, align 8
  store ptr %0, ptr %this, align 8
  %this1 = load ptr, ptr %this, align 8
  %field_ptr = getelementptr %Point, ptr %this1, i32 0, i32 0
  %x = load i64, ptr %field_ptr, align 4
  ret i64 %x
}

define i64 @Point_getY(ptr %0) {
entry:
  %this = alloca ptr, align 8
  store ptr %0, ptr %this, align 8
  %this1 = load ptr, ptr %this, align 8
  %field_ptr = getelementptr %Point, ptr %this1, i32 0, i32 1
  %y = load i64, ptr %field_ptr, align 4
  ret i64 %y
}

define i64 @Point_sum(ptr %0) {
entry:
  %this = alloca ptr, align 8
  store ptr %0, ptr %this, align 8
  %this1 = load ptr, ptr %this, align 8
  %field_ptr = getelementptr %Point, ptr %this1, i32 0, i32 0
  %x = load i64, ptr %field_ptr, align 4
  %this2 = load ptr, ptr %this, align 8
  %field_ptr3 = getelementptr %Point, ptr %this2, i32 0, i32 1
  %y = load i64, ptr %field_ptr3, align 4
  %add = add i64 %x, %y
  ret i64 %add
}

define i64 @Hello_main() {
entry:
  %p = alloca ptr, align 8
  %obj_ptr = call ptr @malloc(i64 ptrtoint (ptr getelementptr (%Point, ptr null, i32 1) to i64))
  %field = getelementptr %Point, ptr %obj_ptr, i32 0, i32 0
  store i64 0, ptr %field, align 4
  %field1 = getelementptr %Point, ptr %obj_ptr, i32 0, i32 1
  store i64 0, ptr %field1, align 4
  call void @Point_Point(ptr %obj_ptr, i64 10, i64 20)
  store ptr %obj_ptr, ptr %p, align 8
  %p2 = load ptr, ptr %p, align 8
  %call = call i64 @Point_getX(ptr %p2)
  %0 = call i32 (ptr, ...) @printf(ptr @fmt_int_nl, i64 %call)
  %p3 = load ptr, ptr %p, align 8
  %call4 = call i64 @Point_getY(ptr %p3)
  %1 = call i32 (ptr, ...) @printf(ptr @fmt_int_nl.1, i64 %call4)
  %p5 = load ptr, ptr %p, align 8
  %call6 = call i64 @Point_sum(ptr %p5)
  %2 = call i32 (ptr, ...) @printf(ptr @fmt_int_nl.2, i64 %call6)
  %p27 = alloca ptr, align 8
  %obj_ptr8 = call ptr @malloc(i64 ptrtoint (ptr getelementptr (%Point, ptr null, i32 1) to i64))
  %field9 = getelementptr %Point, ptr %obj_ptr8, i32 0, i32 0
  store i64 0, ptr %field9, align 4
  %field10 = getelementptr %Point, ptr %obj_ptr8, i32 0, i32 1
  store i64 0, ptr %field10, align 4
  call void @Point_Point(ptr %obj_ptr8, i64 100, i64 200)
  store ptr %obj_ptr8, ptr %p27, align 8
  %p211 = load ptr, ptr %p27, align 8
  %call12 = call i64 @Point_getX(ptr %p211)
  %3 = call i32 (ptr, ...) @printf(ptr @fmt_int_nl.3, i64 %call12)
  %p213 = load ptr, ptr %p27, align 8
  %call14 = call i64 @Point_sum(ptr %p213)
  %4 = call i32 (ptr, ...) @printf(ptr @fmt_int_nl.4, i64 %call14)
  ret i64 0
}
