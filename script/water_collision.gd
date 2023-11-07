extends ColorRect

class_name WaterCollision

var collision:PackedVector3Array

func _process(delta):
	if collision.size() > 0:
		queue_redraw()
	pass

func _draw():
	draw_rect(Rect2(0,0,512,512),Color.BLACK)
	for coll in collision:
		draw_circle(Vector2(coll.x,coll.y),coll.z,Color.RED)
	collision.clear()
	pass

func coll(status:Vector3):
	collision.push_back(status)
	pass
