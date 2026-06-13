module test_no_module;

module test_no_module;

// Test file without module declaration

struct Point {
    int x;
    int y;
}

class Rectangle {
    Point topLeft;
    Point bottomRight;
    
    int area() {
        return (bottomRight.x - topLeft.x) * (bottomRight.y - topLeft.y);
    }
}

enum Color {
    Red,
    Green,
    Blue
}
